#!/bin/sh
# Забирает лимиты из /api/oauth/usage — того же эндпоинта, что и команда /usage.
#
# Зачем отдельный запрос: во вход statusLine приходят только five_hour
# («Current session») и seven_day («All models»), а ПО-МОДЕЛЬНОГО ведра (Fable)
# там нет вовсе — проверено дампом входа. В ответе эндпоинта оно лежит в
# limits[] с kind="weekly_scoped" и scope.model.display_name.
#
# Запускается ФОНОМ из statusline-command.sh: статус перерисовывается постоянно,
# и сетевой запрос на этом пути повесил бы всю строку.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DIR="$HOME/.claude/cache"
CACHE="$DIR/usage.json"
STAMP="$DIR/usage.stamp"
LOCK="$DIR/usage.lock"

mkdir -p "$DIR"

# mkdir атомарен: пока идёт запрос, второй экземпляр просто выходит, а не лезет
# в сеть параллельно. Статус успевает дёрнуть нас десяток раз за эти секунды.
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

# Отметку ставим СРАЗУ, до запроса: иначе неудачная попытка оставила бы кэш
# протухшим, и статус ломился бы в сеть на каждой перерисовке.
touch "$STAMP"

TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
[ -z "$TOKEN" ] && exit 0

BODY=$(curl -s -m 10 \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  https://api.anthropic.com/api/oauth/usage 2>/dev/null)

# В кэш кладём только ответ с limits: пустой или ошибочный затёр бы прошлые
# цифры, и статус показал бы прочерк вместо последних известных значений.
echo "$BODY" | jq -e '.limits' >/dev/null 2>&1 || exit 0
printf '%s' "$BODY" > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
