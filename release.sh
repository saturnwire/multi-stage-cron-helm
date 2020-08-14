#!/usr/bin/env bash
set -eu -o pipefail

# FYI: This Script assumes you have jq installed

token=${GITHUB_TOKEN}
repo_full_name=${GITHUB_REPOSITORY:-$(git config --local remote.origin.url|sed -n 's#.*\:\([^.]*\)\.git#\1#p')}
branch=$(git rev-parse --abbrev-ref HEAD)
version=$(grep 'version:' ./chart/Chart.yaml | awk '{ print $2 }')
name=$(grep 'name:' ./chart/Chart.yaml | awk '{ print $2 }')
helm_package="${name}-${version}.tgz"
index_repo="saturnwire/helm-charts"

generate_post_data() {
cat <<EOF
{
  "tag_name": "$version",
  "target_commitish": "$branch",
  "name": "$version",
  "draft": false,
  "prerelease": false
}
EOF
}

echo "Creating helm package: ${helm_package}"
helm package ./chart

echo "Create release ${version} for repo: ${repo_full_name} branch: ${branch}"
id=$(curl --silent --data "$(generate_post_data)" "https://api.github.com/repos/${repo_full_name}/releases?access_token=${token}" | jq -r .id)

# Get ID of the asset based on given filename.
[ "${id}" ] || { echo "Error: Failed to get release id for tag: ${tag}"; echo "${response}" | awk 'length($0)<100' >&2; exit 1; }

echo "Uploading helm package to release with id: ${id}"
response=$(curl --silent \
-H "Authorization: token ${token}" \
-H "Content-Type: $(file -b --mime-type ${helm_package})" \
--data-binary @${helm_package} \
"https://uploads.github.com/repos/${repo_full_name}/releases/${id}/assets?name=$(basename ${helm_package})")

echo "Removing helm package: ${helm_package}"
rm -rf ${helm_package}

# Check to see if the upload worked
SUB='"state":"uploaded"'
if [[ "${response}" != *"$SUB"* ]]; then
  echo "Error: Failed to upload file to release with id: ${id}"; echo "${response}"
  exit 1
fi

# Trigger the helm-charts repo to rebuild the index file
repo_owner=$(echo $repo_full_name | cut -d'/' -f1)
repo_name=$(echo $repo_full_name | cut -d'/' -f2)
curl -X POST \
	-H "Accept: application/vnd.github.everest-preview+json" \
	-H "Content-Type: application/json" \
	"https://api.github.com/repos/${index_repo}/actions/workflows/release.yml/dispatches?access_token=${HELM_CHARTS_DISPATCH_TOKEN}" -d '{"ref":"master","inputs":{"githubOwner":"${repo_owner}","githubRepo":"${repo_name}"}}'

