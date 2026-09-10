#!/bin/sh
# Answers one question: will an Accessibility grant survive a rebuild?
#
# It survives only if the app's designated requirement is identifier-and-
# certificate based. An ad-hoc signature pins it to a cdhash that changes every
# build, so the grant silently stops applying and Vigil looks un-permitted even
# though it is still ticked in System Settings.
set -e
BUNDLE_ID=zw.co.munyaradzichigangawa.Vigil

echo "1. Code signing identities available"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    security find-identity -v -p codesigning | sed -n 's/^/   /p' | head -5
else
    echo "   NONE. Xcode has no Apple ID."
    echo "   Fix: Xcode > Settings > Accounts > + > Apple ID, then select your"
    echo "        Personal Team under the Vigil target > Signing & Capabilities."
    exit 1
fi

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 \
        -path "*Build/Products/Debug/Vigil.app" -print 2>/dev/null | head -1)
if [ -z "$APP" ]; then
    echo "\n2. No built Vigil.app found. Build once in Xcode, then re-run."
    exit 1
fi

echo "\n2. Designated requirement of $APP"
REQ=$(codesign -d -r- "$APP" 2>&1 | grep "designated" || true)
echo "   $REQ"

echo ""
case "$REQ" in
    *cdhash*)
        echo "RESULT: STILL AD-HOC. The grant will break on every rebuild."
        echo "        Select a Team in Signing & Capabilities, rebuild, re-run this."
        exit 1
        ;;
    *certificate*|*anchor*)
        echo "RESULT: STABLE. The Accessibility grant will now survive rebuilds."
        echo "        Grant it once more (the old entry is tied to the old signature):"
        echo "          tccutil reset Accessibility $BUNDLE_ID"
        exit 0
        ;;
    *)
        echo "RESULT: could not read the requirement. Is the app signed at all?"
        exit 1
        ;;
esac
