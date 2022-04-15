#!/bin/bash
# this will update the arch.pkr.hcl file with the current netboot image checksum.
set -euxo pipefail
iso_url="$(cat arch.pkr.hcl | perl -n -e '/(https?:\/\/.+\/archlinux-.+\.iso)/ && print "$1"')"
iso_checksum_url="$(dirname $iso_url)/sha256sums.txt"
curl -O --silent --show-error $iso_checksum_url
iso_checksum=$(grep $(basename $iso_url) sha256sums.txt | awk '{print $1}')
for f in arch*.pkr.hcl; do
    sed -i -E "s,(\"sha256:[a-z0-9:]+\"),\"sha256:$iso_checksum\",g" $f
done
rm sha256sums.txt
echo 'iso_checksum updated successfully'
