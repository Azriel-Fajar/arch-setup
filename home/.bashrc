#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export PATH="$HOME/.npm-global/bin:$PATH"
export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:/home/azriel/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Auto-repair claude native binary if postinstall didn't run
claude() {
  local pkg="$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code"
  local bin="$pkg/bin/claude.exe"
  local src="$pkg/node_modules/@anthropic-ai/claude-code-linux-x64/claude"
  if [ "$(stat -c%s "$bin" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "claude: native binary missing, repairing..." >&2
    if [ "$(stat -c%s "$src" 2>/dev/null || echo 0)" -lt 100000 ]; then
      echo "claude: native package missing too, reinstalling from npm..." >&2
      npm install -g "@anthropic-ai/claude-code@$(node -p "require('"'"'$pkg/package.json'"'"').version")" || return 1
    else
      node "$pkg/install.cjs" || return 1
    fi
  fi
  command claude "$@"
}
