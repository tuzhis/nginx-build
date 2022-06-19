#!/usr/bin/env bash
# Run as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Make script exit if a simple command fails and
# Make script print commands being executed
set -e -x

# Ensure curl is installed
#apt-get update && apt-get install curl -y

# Set URLs to the source directories
source_pcre=https://onboardcloud.dl.sourceforge.net/project/pcre/pcre/8.45/
source_zlib=https://zlib.net/
source_openssl=https://www.openssl.org/source/
source_nginx=https://nginx.org/download/

# Look up latest versions of each package
version_pcre=pcre-8.45
version_zlib=$(curl -sL ${source_zlib} | grep -Eo 'zlib\-[0-9.]+[0-9]' | sort -V | tail -n 1)
version_openssl=$(curl -sL ${source_openssl} | grep -Po 'openssl\-[0-9]+\.[0-9]+\.[0-9]+[a-z]?(?=\.tar\.gz)' | sort -V | tail -n 1)
source_nginx=https://nginx.org/download/
version_nginx=$(curl -sL ${source_nginx} | grep -Eo 'nginx\-[0-9.]+[13579]\.[0-9]+' | sort -V | tail -n 1)

# Set OpenPGP keys used to sign downloads
opgp_pcre=45F68D54BBE23FB3039B46E59766E084FB0F43D8
opgp_zlib=5ED46A6721D365587791E2AA783FCD8E58BCAFBA
opgp_openssl=8657ABB260F056B1E5190839D9C4D26D0E604491
opgp_nginx=B0F4253373F8F6F510D42178520A9993A1C052F8

# Set where OpenSSL and NGINX will be built
bpath=/tmp/nginx-build
mainpath=/work/local/nginx
runpath=/work/rundata/nginx
configpath=/work/data/nginx
output_bin=${mainpath}/bin/nginx

# Make a "today" variable for use in back-up filenames later
today=$(date +"%Y-%m-%d")

# Clean out any files from previous runs of this script
rm -rf "$bpath" 
mkdir "$bpath"


# Download the source files
curl -L "${source_pcre}${version_pcre}.tar.gz" -o "${bpath}/pcre.tar.gz"
curl -L "${source_zlib}${version_zlib}.tar.gz" -o "${bpath}/zlib.tar.gz"
curl -L "${source_openssl}${version_openssl}.tar.gz" -o "${bpath}/openssl.tar.gz"
curl -L "${source_nginx}${version_nginx}.tar.gz" -o "${bpath}/nginx.tar.gz"

# Download the signature files
curl -L "${source_pcre}${version_pcre}.tar.gz.sig" -o "${bpath}/pcre.tar.gz.sig"
curl -L "${source_zlib}${version_zlib}.tar.gz.asc" -o "${bpath}/zlib.tar.gz.asc"
curl -L "${source_openssl}${version_openssl}.tar.gz.asc" -o "${bpath}/openssl.tar.gz.asc"
curl -L "${source_nginx}${version_nginx}.tar.gz.asc" -o "${bpath}/nginx.tar.gz.asc"

# Verify the integrity and authenticity of the source files through their OpenPGP signature
cd "$bpath"
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
gpg --keyserver keyserver.ubuntu.com --recv-keys "$opgp_pcre" "$opgp_zlib" "$opgp_openssl" "$opgp_nginx"
gpg --batch --verify pcre.tar.gz.sig pcre.tar.gz
gpg --batch --verify zlib.tar.gz.asc zlib.tar.gz
gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz

# Expand the source files
cd "$bpath"
for archive in ./*.tar.gz; do
  tar xzf "$archive"
done

# Clean up source files
rm -rf \
  "$GNUPGHOME" \
  "$bpath"/*.tar.*

# Test to see if our version of gcc supports __SIZEOF_INT128__
if gcc -dM -E - </dev/null | grep -q __SIZEOF_INT128__
then
  ecflag="enable-ec_nistp_64_gcc_128"
else
  ecflag=""
fi

# Build NGINX, with various modules included/excluded
cd "$bpath/$version_nginx"
./configure \
--prefix=${mainpath} \
--modules-path=${mainpath}/modules \
--sbin-path=${output_bin} \
--conf-path=${configpath}/nginx.conf \
--http-log-path=${runpath}/access.log \
--error-log-path=${runpath}/error.log \
--http-client-body-temp-path=${runpath}/body \
--http-fastcgi-temp-path=${runpath}/fastcgi \
--http-proxy-temp-path=${runpath}/proxy \
--http-scgi-temp-path=${runpath}/scgi \
--http-uwsgi-temp-path=${runpath}/uwsgi \
--pid-path=/var/run/nginx.pid \
--lock-path=/var/run/nginx.lock \
--with-openssl-opt="no-weak-ssl-ciphers no-ssl3 no-shared $ecflag -DOPENSSL_NO_HEARTBEATS -fstack-protector-strong" \
--with-cc-opt="-O3 -fPIE -fstack-protector-strong -Wformat -Werror=format-security" \
--with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro" \
--with-pcre="$bpath/$version_pcre" \
--with-zlib="$bpath/$version_zlib" \
--with-openssl="$bpath/$version_openssl" \
--user=nginx \
--group=nginx \
--with-file-aio \
--with-http_auth_request_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_mp4_module \
--with-http_realip_module \
--with-http_secure_link_module \
--with-http_slice_module \
--with-http_ssl_module \
--with-http_stub_status_module \
--with-http_sub_module \
--with-http_v2_module \
--with-pcre-jit \
--with-stream \
--with-stream_ssl_module \
--with-stream_ssl_preread_module \
--with-stream_realip_module  \
--with-http_xslt_module \
--with-http_geoip_module \
--with-http_image_filter_module \
--with-threads \
--without-http_empty_gif_module \
--without-http_geo_module \
--without-http_split_clients_module \
--without-http_ssi_module 
make -j"$(nproc)"
make install -j"$(nproc)"
make clean
strip -s ${output_bin}
output_name="$1"
cd ${mainpath}
tar czvf /tmp/${output_name}.tar.gz ./
