#!/bin/sh
# Claude Code statusLine — полная информация
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
input=$(cat)

# Ширина окна. В самом входе statusLine её нет, но процессу она достаётся
# через COLUMNS и tput — проверено дампом окружения. /dev/tty тут недоступен
# («Device not configured»), так что stty size не годится.
cols=${COLUMNS:-0}
[ "$cols" -le 0 ] 2>/dev/null && cols=$(tput cols 2>/dev/null || echo 0)
[ "$cols" -le 0 ] 2>/dev/null && cols=120

# Видимая длина строки: без ANSI-кодов и в СИМВОЛАХ, а не байтах — в псевдо-
# графике и кириллице символ занимает 2-3 байта, и по байтам ширина завышается
# втрое.
ESC=$(printf '\033')
vislen() {
  printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | wc -m | tr -d ' '
}

# Модель
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "—"')

# Рабочая директория (сокращаем HOME до ~)
cwd=$(echo "$input" | jq -r '.cwd // ""')
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Git-ветка и версия проекта — по текущей директории
git_branch=""
proj_ver=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$git_branch" ] && [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -1)" ]; then
    git_branch="${git_branch}*"
  fi
  for pj in "$cwd/app/package.json" "$cwd/package.json"; do
    if [ -f "$pj" ]; then
      proj_ver=$(jq -r '.version // empty' "$pj" 2>/dev/null)
      [ -n "$proj_ver" ] && proj_ver="v${proj_ver}" && break
    fi
  done
fi

# Использование контекста
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Текущие токены из последнего вызова
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')

# Лимиты Claude.ai
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Недельное ведро Fable. Во входе statusLine его нет — только five_hour
# («Current session») и seven_day («All models»), поэтому берём из кэша,
# который наполняет usage-fetch.sh фоном. Здесь только чтение файла: сеть
# на пути перерисовки статуса недопустима.
usage_cache="$HOME/.claude/cache/usage.json"
usage_stamp="$HOME/.claude/cache/usage.stamp"
usage_ttl=120
now=$(date +%s)
stamp_age=$(( now - $(stat -f %m "$usage_stamp" 2>/dev/null || echo 0) ))
if [ "$stamp_age" -gt "$usage_ttl" ]; then
  ( "$HOME/.claude/usage-fetch.sh" >/dev/null 2>&1 & ) 2>/dev/null
fi
fable_pct=""
if [ -f "$usage_cache" ]; then
  fable_pct=$(jq -r '[.limits[]? | select(.kind=="weekly_scoped")
                      | select(.scope.model.display_name=="Fable") | .percent]
                     | first // empty' "$usage_cache" 2>/dev/null)
fi

# Версия
version=$(echo "$input" | jq -r '.version // ""')

# Vim режим
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')

# Агент
agent_name=$(echo "$input" | jq -r '.agent.name // empty')

# Текущая задача — последняя реплика пользователя из транскрипта.
# В самом входе statusLine её нет, зато есть transcript_path. Читаем ХВОСТ
# файла (он растёт до десятков мегабайт, а статус перерисовывается постоянно),
# отбрасываем служебное: tool_result (не строка и не text-блок), isMeta,
# слэш-команды и <system-reminder> — они начинаются с угловой скобки.
# Обрезаем длину через jq, а не cut: cut на macOS режет БАЙТЫ, и кириллица
# разваливается на середине символа.
task=""
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  task=$(tail -n 400 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="user" and (.isMeta // false | not))
             | .message.content
             | (if type=="string" then .
                else (map(select(.type=="text") | .text) | join(" ")) end)
             | gsub("\\[Image #\\d+\\]"; "") | gsub("\\s+"; " ")' 2>/dev/null \
    | grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*<' | tail -1)
  task=$(printf '%s' "$task" \
    | jq -Rr 'sub("^\\s+";"") | if length > 120 then .[0:120] + "…" else . end' 2>/dev/null)
fi

# Везде показываем ОСТАТОК, а не расход: вопрос всегда «сколько ещё есть»,
# и полоска при выгорании пустеет, а не наполняется.

# Горизонтальная полоска остатка. Рисуется ЛИНИЕЙ ━, а не блоком █: блок занимает
# всю высоту клетки и выглядит плашкой, а нужна тонкая шкала.
#
# Дорожка — ТОТ ЖЕ символ ━, только бледным тоном. Именно так устроен бар в
# референсе: заполнение и дорожка одной толщины, отличаются только цветом.
# Разной толщиной (━ против ─) шкала распадалась на две разные линии.
#   $1 — остаток в процентах, $2 — ширина в клетках
gauge() {
  g_pct=$1
  g_w=$2
  # +50 перед делением — округление к ближайшему, иначе 99% не докрашивает клетку
  g_fill=$(( (g_pct * g_w + 50) / 100 ))
  [ "$g_fill" -gt "$g_w" ] && g_fill=$g_w
  [ "$g_fill" -lt 0 ] && g_fill=0
  # Пока остаток не ноль, горит хотя бы одна клетка: иначе на 5% полоска
  # обнулялась целиком и сигнал пропадал ровно там, где он нужнее всего.
  [ "$g_fill" -eq 0 ] && [ "$g_pct" -gt 0 ] && g_fill=1

  g_bar=""
  g_i=0
  while [ "$g_i" -lt "$g_fill" ]; do g_bar="${g_bar}━"; g_i=$((g_i + 1)); done
  g_track=""
  while [ "$g_i" -lt "$g_w" ]; do g_track="${g_track}━"; g_i=$((g_i + 1)); done

  # Дорожка — приглушённый серо-синий. Бледно-голубой 152 бил по глазам, а
  # тёмно-серый (238 и ниже) проваливался в фон и шкалы было не видно;
  # 240 читается спокойно и на тёмной теме, и на светлой.
  printf '%s%s\033[38;5;240m%s\033[0m' "$(lvl_color "$g_pct")" "$g_bar" "$g_track"
}

# Цвет-светофор по остатку. Им красится и столбик, и его цифра в подписи —
# так столбик и подпись связываются глазом без разглядывания порядка.
# Тона взяты приглушённые: чистые 33/214/203 светили как неон и били по глазам
# в строке, которая висит перед носом постоянно. Сигнальную роль они сохраняют —
# различаются по тону, а не по яркости.
lvl_color() {
  if [ "$1" -le 20 ]; then
    printf '\033[38;5;131m'   # приглушённый красный: почти всё сожжено
  elif [ "$1" -le 50 ]; then
    printf '\033[38;5;137m'   # песочный: перевалило за половину
  else
    printf '\033[38;5;67m'    # серо-синий: запас есть
  fi
}

# Сборка строки
parts=""

# Директория
if [ -n "$short_cwd" ]; then
  parts="${parts}$(printf '\033[0;36m')${short_cwd}$(printf '\033[0m')"
fi

# Ветка и версия проекта
if [ -n "$git_branch" ]; then
  parts="${parts} $(printf '\033[38;5;108m')${git_branch}$(printf '\033[0m')"
fi
if [ -n "$proj_ver" ]; then
  parts="${parts} $(printf '\033[38;5;245m')${proj_ver}$(printf '\033[0m')"
fi

# Модель
if [ -n "$model" ] && [ "$model" != "—" ]; then
  [ -n "$parts" ] && parts="${parts} $(printf '\033[0;37m')│$(printf '\033[0m') "
  parts="${parts}$(printf '\033[0;33m')${model}$(printf '\033[0m')"
fi

# Версия Claude Code
if [ -n "$version" ]; then
  parts="${parts} $(printf '\033[0;90m')v${version}$(printf '\033[0m')"
fi

# Названия ведёр — как в окне Usage: ctx — контекст сессии, 5h — Current
# session, all — All models (это seven_day из входа), fable — ведро Fable.
lbl=$(printf '\033[38;5;245m')   # названия — спокойным серым, но читаемым
off=$(printf '\033[0m')
# Ширина шкалы — 10 клеток: клетка = ровно 10%, полоска сходится с цифрой без
# пересчёта. При некратной десяти ширине округление врёт до половины клетки.
gauge_w=10
bars=""

# Добавляет ведро: подпись, полоска, процент.
#   $1 — название, $2 — остаток в процентах
add_metric() {
  [ -n "$bars" ] && bars="${bars}  "
  bars="${bars}${lbl}$1${off} $(gauge "$2" "$gauge_w") ${lbl}$2%${off}"
}

if [ -n "$remaining_pct" ]; then
  add_metric ctx "$(printf '%.0f' "$remaining_pct")"
fi
if [ -n "$five_pct" ]; then
  add_metric 5h "$((100 - $(printf '%.0f' "$five_pct")))"
fi
if [ -n "$seven_pct" ]; then
  add_metric all "$((100 - $(printf '%.0f' "$seven_pct")))"
fi
if [ -n "$fable_pct" ]; then
  add_metric fable "$((100 - $(printf '%.0f' "$fable_pct")))"
fi

# Токены текущего запроса
if [ -n "$input_tokens" ]; then
  parts="${parts} $(printf '\033[38;5;240m')(${input_tokens}t)$(printf '\033[0m')"
fi

# Имя сессии не показываем: Claude Code сочиняет его из ПЕРВОГО сообщения
# и больше не меняет, так что через полчаса оно врёт про то, чем занимаемся.
# Актуальное положение дел даёт блок задачи в конце строки.

# Агент
if [ -n "$agent_name" ]; then
  [ -n "$parts" ] && parts="${parts} $(printf '\033[0;37m')│$(printf '\033[0m') "
  parts="${parts}$(printf '\033[0;95m')agent:${agent_name}$(printf '\033[0m')"
fi

# Vim режим
if [ -n "$vim_mode" ]; then
  [ -n "$parts" ] && parts="${parts} $(printf '\033[0;37m')│$(printf '\033[0m') "
  if [ "$vim_mode" = "INSERT" ]; then
    vim_color=$(printf '\033[0;32m')
  else
    vim_color=$(printf '\033[0;33m')
  fi
  parts="${parts}${vim_color}${vim_mode}$(printf '\033[0m')"
fi

# Шкалы просятся СПРАВА в той же строке, но лезут туда только если помещаются
# целиком: иначе терминал переносит их посреди полоски, и шкала разваливается
# на две половины. Не влезли — уходят на свою строку целиком.
if [ -n "$bars" ]; then
  sep=" $(printf '\033[38;5;240m')│$(printf '\033[0m') "
  if [ "$(( $(vislen "$parts") + 3 + $(vislen "$bars") ))" -le "$cols" ]; then
    parts="${parts}${sep}${bars}"
    bars=""
  fi
fi

printf '%s' "$parts"
[ -n "$bars" ] && printf '\n%s' "$bars"
if [ -n "$task" ]; then
  printf '\n%s❯ %s%s' "$(printf '\033[0;97m')" "$task" "$(printf '\033[0m')"
fi
