#!/usr/bin/env bash
set -eu -o pipefail

text=${1:-'Update in [CHANGELOG](../../../blob/master/CHANGELOG.md).'}
token=${GITHUB_TOKEN}
repo_full_name=${GITHUB_REPOSITORY:-$(git config --local remote.origin.url|sed -n 's#.*\:\([^.]*\)\.git#\1#p')}
branch=$(git rev-parse --abbrev-ref HEAD)
version=$(grep 'version:' ./chart/Chart.yaml | awk '{ print $2 }')
name=$(grep 'name:' ./chart/Chart.yaml | awk '{ print $2 }')
helm_package="${name}-${version}.tgz"

generate_post_data() {
cat <<EOF
{
  "tag_name": "$version",
  "target_commitish": "$branch",
  "name": "$version",
  "body": "$text",
  "draft": false,
  "prerelease": false
}
EOF
}

echo "Creating helm package: ${helm_package}"
helm package ./chart

echo "Create release ${version} for repo: ${repo_full_name} branch: ${branch}"
response=$(curl --data "$(generate_post_data)" "https://api.github.com/repos/${repo_full_name}/releases?access_token=${token}")

# Get ID of the asset based on given filename.
eval $(echo "${response}" | grep -m 1 "id.:" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
[ "${id}" ] || { echo "Error: Failed to get release id for tag: ${tag}"; echo "${response}" | awk 'length($0)<100' >&2; exit 1; }

echo "Uploading helm package to release with id: ${id}"
response2=$(curl \
-H "Authorization: token ${token}" \
-H "Content-Type: $(file -b --mime-type ${helm_package})" \
--data-binary @${helm_package} \
"https://uploads.github.com/repos/${repo_full_name}/releases/${id}/assets?name=$(basename ${helm_package})")

echo "Removing helm package: ${helm_package}"
rm -rf ${helm_package}

# Check to see if the upload worked
SUB='"state":"uploaded"'
if [[ "${response2}" != *"$SUB"* ]]; then
  echo "Error: Failed to upload file to release with id: ${id}"; echo "${response}"
  exit 1
fi
