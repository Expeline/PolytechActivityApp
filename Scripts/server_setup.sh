#!/bin/zsh
# Prepares PolyServer on this Mac: PostgreSQL from Homebrew, databases, migrations.
set -euo pipefail
cd "$(dirname "$0")/../Server"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

if ! pg_isready -q; then
  formula=$(brew list --formula | grep -E '^postgresql(@[0-9]+)?$' | sort -V | tail -1)
  [[ -z "$formula" ]] && { brew install postgresql@18; formula=postgresql@18; }
  brew services start "$formula"
  until pg_isready -q; do sleep 1; done
fi

for db in polytech polytech_test; do
  psql -lqt | cut -d'|' -f1 | grep -qw "$db" || createdb "$db"
done

swift build
swift run PolyServer migrate --yes
echo "Готово. Запуск сервера: cd Server && swift run PolyServer serve"
