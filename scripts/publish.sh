#!/bin/bash
set -euo pipefail

Organization="${Organization:-OkraLinux}"
Repository="${Repository:-oaa-packages}"
ReleaseTag="${ReleaseTag:-packages}"
SourceDirectory="$(cd "$(dirname "$0")/.." && pwd)"
WorkDirectory="${RUNNER_TEMP:-/tmp}/okra-publish"
Token="${PublishToken:?missing PublishToken}"

Api="https://api.github.com/repos/${Organization}/${Repository}"

echo "== syncing recipe and metadata"
rm -rf "$WorkDirectory"
git clone --depth 1 "https://x-access-token:${Token}@github.com/${Organization}/${Repository}.git" "$WorkDirectory"

mkdir -p "$WorkDirectory/packages" "$WorkDirectory/scripts"
cp -f "$SourceDirectory"/packages/*.conf "$WorkDirectory/packages/"
cp -f "$SourceDirectory"/scripts/build-package.sh "$WorkDirectory/scripts/"

rm -rf "$WorkDirectory/out"
mkdir -p "$WorkDirectory/out"
find "$SourceDirectory/out" -type f \( -name '*.sources' -o -name '*.sha256' \) -exec cp -a {} "$WorkDirectory/out/" \;

cd "$WorkDirectory"
git config user.name "OkraLinux Build"
git config user.email "build@okralinux.cn"
git add -A
if git diff --cached --quiet; then
	echo "no metadata change"
else
	git commit -m "update recipes and checksums"
	git push origin HEAD:main
fi

echo "== uploading artifacts to release ${ReleaseTag}"
ReleaseId="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/tags/${ReleaseTag}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"

if [ -z "$ReleaseId" ]; then
	curl -sS -X POST -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" \
		"${Api}/releases" \
		-d "{\"tag_name\":\"${ReleaseTag}\",\"name\":\"${ReleaseTag}\",\"body\":\"OAA packages\"}" > /dev/null
	ReleaseId="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/tags/${ReleaseTag}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
fi

[ -n "$ReleaseId" ] || { echo "cannot resolve release" >&2; exit 1; }

for Archive in "$SourceDirectory"/out/*/*.oaa; do
	[ -f "$Archive" ] || continue
	ArchiveName="$(basename "$Archive")"
	Existing="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/${ReleaseId}/assets?per_page=100" | python3 -c "import json,sys;print([a['id'] for a in json.load(sys.stdin) if a['name']=='${ArchiveName}'])" | tr -d '[]')"
	if [ -n "$Existing" ]; then
		curl -sS -X DELETE -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/assets/${Existing}" > /dev/null
	fi
	UploadUrl="https://uploads.github.com/repos/${Organization}/${Repository}/releases/${ReleaseId}/assets?name=${ArchiveName}"
	curl -sS -X POST -H "Authorization: Bearer ${Token}" -H "Content-Type: application/octet-stream" --data-binary "@${Archive}" "$UploadUrl" > /dev/null
	echo "uploaded $ArchiveName"
done

echo "published to ${Organization}/${Repository}"