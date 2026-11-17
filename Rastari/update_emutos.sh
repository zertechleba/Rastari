#!/bin/bash
# Stáhne nejnovější vydání EmuTOS (open-source TOS pro Atari ST) a nastaví ho
# jako ROM v Hatari konfiguraci, kterou Rastari spouští.
# Zdroj: https://emutos.sourceforge.io/download.html
#
# Použití: ./update_emutos.sh
# Přepsat cesty lze přes proměnné prostředí EMUTOS_DIR a HATARI_CFG_DIR.

BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NOCOLOR='\033[0m'

EMUTOS_DIR=${EMUTOS_DIR:-/usr/local/rastari/emutos}
HATARI_CFG_DIR=${HATARI_CFG_DIR:-/root/.hatari}
EMUTOS_CFG="$HATARI_CFG_DIR/EmuTOS-ST.cfg"
DOWNLOAD_PAGE=https://emutos.sourceforge.io/en/download.html
RELEASES_PAGE=https://sourceforge.net/projects/emutos/files/emutos/

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

fetch() { # url cíl
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 --connect-timeout 20 -o "$2" "$1"
	else
		wget -q --tries=3 --timeout=20 -O "$2" "$1"
	fi
}

fail() {
	echo -e "${RED}EmuTOS: $1${NOCOLOR}"
	exit 1
}

echo -e "${BLUE}--== Hledám nejnovější EmuTOS ==--${NOCOLOR}"

# 1) Zjistit nejnovější vydání (zip pro Atari ST 512 KB)
zip_name=""
for page in "$DOWNLOAD_PAGE" "$RELEASES_PAGE"; do
	if fetch "$page" "$TMP/page.html" 2>/dev/null; then
		zip_name=$(grep -oE 'emutos-512k-[0-9][0-9.]*\.zip' "$TMP/page.html" | sort -uV | tail -1)
		[ -n "$zip_name" ] && break
	fi
done
[ -n "$zip_name" ] || fail "nepodařilo se zjistit nejnovější verzi (zkontroluj připojení k internetu)"

version=${zip_name#emutos-512k-}
version=${version%.zip}

installed=""
[ -f "$EMUTOS_DIR/VERSION" ] && installed=$(<"$EMUTOS_DIR/VERSION")
if [ "$installed" = "$version" ] && [ -f "$EMUTOS_DIR/etos512.img" ]; then
	echo -e "${BLUE}--== EmuTOS $version je aktuální ==--${NOCOLOR}"
else
	# 2) Stáhnout a rozbalit zip
	echo -e "${YELLOW}Stahuji EmuTOS $version...${NOCOLOR}"
	url="https://sourceforge.net/projects/emutos/files/emutos/$version/$zip_name/download"
	fetch "$url" "$TMP/$zip_name" || fail "stahování $zip_name selhalo"
	mkdir -p "$TMP/x" && unzip -q -o "$TMP/$zip_name" -d "$TMP/x" || fail "rozbalení $zip_name selhalo"

	# 3) Vybrat ROM image (preferovaně anglická verze, jinak první etos512*.img)
	img=$(find "$TMP/x" -iname 'etos512*.img' | sort | grep -i 'us\.img$' | head -1)
	[ -n "$img" ] || img=$(find "$TMP/x" -iname 'etos512*.img' | sort | head -1)
	[ -n "$img" ] || fail "v archivu není ROM image etos512*.img"

	# 4) Nainstalovat pod stálým názvem, aby se Hatari konfigurace nemusela měnit
	mkdir -p "$EMUTOS_DIR" || fail "nelze vytvořit $EMUTOS_DIR"
	cp "$img" "$EMUTOS_DIR/etos512.img" || fail "kopírování ROM selhalo"
	echo "$version" > "$EMUTOS_DIR/VERSION"
	echo -e "${BLUE}--== EmuTOS $version nainstalován do $EMUTOS_DIR ==--${NOCOLOR}"
fi

# 5) Hatari konfigurace s EmuTOS jako ROM
mkdir -p "$HATARI_CFG_DIR"
if [ ! -f "$EMUTOS_CFG" ]; then
	# šablona = první existující konfigurace (kromě naší); jinak není z čeho vycházet
	template=$(ls "$HATARI_CFG_DIR"/*.cfg 2>/dev/null | grep -v "EmuTOS-ST.cfg" | head -1)
	if [ -z "$template" ]; then
		echo -e "${YELLOW}Žádná Hatari konfigurace neexistuje. Vytvoř jednu v Hatari a spusť tento skript znovu.${NOCOLOR}"
		exit 0
	fi
	cp "$template" "$EMUTOS_CFG"
	echo -e "${BLUE}Vytvořena konfigurace $EMUTOS_CFG podle $(basename "$template")${NOCOLOR}"
fi
sed -i "s|^szTosImageFileName = .*|szTosImageFileName = $EMUTOS_DIR/etos512.img|" "$EMUTOS_CFG"
echo -e "${BLUE}--== EmuTOS nastaven v $(basename "$EMUTOS_CFG") ==--${NOCOLOR}"
