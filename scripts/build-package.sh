#!/bin/bash
set -euo pipefail

PackageName="${1:?usage: build-package.sh <package>}"
RepositoryRoot="$(cd "$(dirname "$0")/.." && pwd)"
RecipeFile="$RepositoryRoot/packages/${PackageName}.conf"

[ -f "$RecipeFile" ] || { echo "recipe not found: $RecipeFile" >&2; exit 1; }

Name=""
Version=""
Release=1
Namespace=app
Description=""
Url=""
Sha256=""
BuildSystem=autoconf
InstallTarget=install
ConfigureFlags=()
MakeFlags=()
Dependencies=()
ExtraPackages=()

. "$RecipeFile"

[ -n "$Name" ] || Name="$PackageName"
[ -n "$Version" ] || { echo "recipe missing Version" >&2; exit 1; }
[ -n "$Url" ] || { echo "recipe missing Url" >&2; exit 1; }

WorkRoot="${RUNNER_TEMP:-/tmp}/okra-build/${Name}"
SourceDirectory="$WorkRoot/source"
BuildDirectory="$WorkRoot/build"
InstallRoot="$WorkRoot/install"
PackageDirectory="$WorkRoot/package"
OutputDirectory="$RepositoryRoot/out"
Archive="$WorkRoot/$(basename "$Url")"

rm -rf "$WorkRoot"
mkdir -p "$WorkRoot" "$OutputDirectory"

echo "== fetching source"
curl -fsSL --http1.1 --retry 5 --retry-delay 3 --retry-all-errors -o "$Archive" "$Url"
SourceSum="$(sha256sum "$Archive" | awk '{print $1}')"
echo "source sha256 $SourceSum"
if [ -n "$Sha256" ] && [ "$Sha256" != "$SourceSum" ]; then
	echo "checksum mismatch for $Archive" >&2
	exit 1
fi

mkdir -p "$SourceDirectory"
tar -xf "$Archive" -C "$SourceDirectory" --strip-components=1

if declare -f Build > /dev/null; then
	echo "== custom build"
	Build
else
	mkdir -p "$BuildDirectory"
	cd "$BuildDirectory"
	echo "== configure"
	"$SourceDirectory/configure" --prefix=/usr ${ConfigureFlags[@]+"${ConfigureFlags[@]}"}
	echo "== make"
	make -j"$(nproc)" ${MakeFlags[@]+"${MakeFlags[@]}"}
	echo "== install"
	make DESTDIR="$InstallRoot" ${MakeFlags[@]+"${MakeFlags[@]}"} "$InstallTarget"
fi

echo "== assembling package"
mkdir -p "$PackageDirectory/rootfs" "$PackageDirectory/scripts"
cp -a "$InstallRoot"/. "$PackageDirectory/rootfs"/
find "$PackageDirectory" -name '.l2s.*' -delete
find "$PackageDirectory/rootfs" -name '*.la' -delete

InstalledSize="$(du -sm "$PackageDirectory/rootfs" | cut -f1)"

FileList=""
for SearchDirectory in usr/bin usr/sbin usr/lib usr/libexec lib lib64 sbin bin; do
	Target="$PackageDirectory/rootfs/$SearchDirectory"
	[ -d "$Target" ] || continue
	while IFS= read -r FoundFile; do
		FileList="${FileList}${SearchDirectory}/${FoundFile}"$'\n'
	done < <(cd "$Target" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | sort)
done

{
	echo "name: $Name"
	echo "namespace: $Namespace"
	echo "version: $Version"
	echo "release: $Release"
	echo "description: \"$Description\""
	echo "architecture: aarch64"
	echo "maintainer: \"OkraLinux Team <maintainer@okralinux.cn>\""
	echo "installed_size: $InstalledSize"
	if [ "${#Dependencies[@]}" -gt 0 ]; then
		echo "dependencies:"
		for Dependency in "${Dependencies[@]}"; do
			echo "  - $Dependency"
		done
	else
		echo "dependencies: []"
	fi
	echo "files:"
	if [ -n "$FileList" ]; then
		while IFS= read -r ListedFile; do
			[ -n "$ListedFile" ] || continue
			echo "  - /$ListedFile"
		done <<< "$FileList"
	else
		echo "  - /"
	fi
} > "$PackageDirectory/meta.yaml"

ArchiveName="${Name}-${Version}-${Release}.aarch64.oaa"
ArtifactDirectory="${RUNNER_TEMP:-/tmp}/okra-artifacts"
PackageOutput="$ArtifactDirectory/$Name"
rm -rf "$PackageOutput"
mkdir -p "$PackageOutput"
cd "$PackageDirectory"
tar --zstd -cf "$PackageOutput/$ArchiveName" meta.yaml rootfs scripts
cd "$PackageOutput"
sha256sum "$ArchiveName" > "${ArchiveName}.sha256"

MetadataOutput="$OutputDirectory/$Name"
rm -rf "$MetadataOutput"
mkdir -p "$MetadataOutput"
cp -f "${ArchiveName}.sha256" "$MetadataOutput/"
echo "${SourceSum}  ${Url}" > "$MetadataOutput/${Name}-${Version}-${Release}.sources"

echo "== built $ArchiveName"
cat "${ArchiveName}.sha256"
head -c 400 "$PackageDirectory/meta.yaml"
echo
