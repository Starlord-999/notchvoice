#!/bin/sh
# One-time setup: Python env for Laya, model downloads, OmniVoice binary, app build.
# Needs: Homebrew whisper-cpp, uv, cmake, git. Re-running is safe (skips what exists).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
M=models
mkdir -p $M vendor

command -v whisper-server >/dev/null || brew install whisper-cpp

# Laya sidecar
[ -d sidecar/.venv ] || uv venv -q --python 3.12 sidecar/.venv
uv pip install -q --python sidecar/.venv laya-mlx
sidecar/.venv/bin/python -c "import laya_mlx as l; l.load('aac6fef/laya-multilingual-mlx')"

# Whisper
[ -f $M/ggml-base.en.bin ] || curl -fL -o $M/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# OmniVoice (VoiceStudio's GGUF engine) — pinned to VoiceStudio's quant_map.json revisions
OV=https://huggingface.co/Serveurperso/OmniVoice-GGUF/resolve/361609388ae572a820d085185bbbe2a2aac4b30e
for f in omnivoice-base-Q8_0.gguf omnivoice-tokenizer-Q8_0.gguf; do
  [ -f $M/$f ] || curl -fL -o $M/$f $OV/$f
done
BIN=vendor/VoiceStudio/bin/omnivoice-tts-darwin-arm64
[ -d vendor/VoiceStudio ] || git clone -q --depth 1 https://github.com/debpalash/VoiceStudio vendor/VoiceStudio
if [ ! -s $BIN ]; then
  (cd vendor/VoiceStudio && scripts/build-omnivoice-tts.sh --platform darwin-arm64 \
    --commit-sha 886fc079838ca7400cb2b42b36e2a65aa1daabe8)
  # upstream script leaves an rpath into a deleted temp dir
  install_name_tool -add_rpath @executable_path $BIN
  codesign -f -s - $BIN
fi

# Stable self-signed code-signing identity, so macOS keeps mic/Accessibility grants across rebuilds.
if ! security find-identity -p codesigning | grep -q "NotchVoice Local Signing"; then
  T=$(mktemp -d)
  printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=NotchVoice Local Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > $T/cfg
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout $T/key.pem -out $T/cert.pem -days 3650 -config $T/cfg
  P=$(uuidgen)
  /usr/bin/openssl pkcs12 -export -inkey $T/key.pem -in $T/cert.pem -out $T/id.p12 -passout pass:$P -name "NotchVoice Local Signing"
  security import $T/id.p12 -k ~/Library/Keychains/login.keychain-db -P "$P" -T /usr/bin/codesign
  rm -rf $T
fi

NotchVoice/build.sh
echo "Done. Open NotchVoice/build/NotchVoice.app"
