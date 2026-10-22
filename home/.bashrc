#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# ble.sh: fish-style autosuggestions + syntax highlighting (attached at end of file)
[[ -f /usr/share/blesh/ble.sh ]] && source /usr/share/blesh/ble.sh --noattach

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

# ── History ─────────────────────────────────────────
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend autocd cdspell globstar checkwinsize

# ── Modern CLI replacements (only if installed) ─────
if command -v eza >/dev/null; then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -l --icons=auto --git --group-directories-first'
  alias la='eza -la --icons=auto --git --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto'
fi
command -v bat >/dev/null && alias cat='bat --paging=never --style=plain'
command -v zoxide >/dev/null && eval "$(zoxide init bash --cmd cd)"

# ── Kitty kittens ───────────────────────────────────
if [[ $TERM == xterm-kitty ]]; then
  alias icat='kitten icat'
  alias kssh='kitten ssh'
  alias kdiff='kitten diff'
fi

# ── fzf: Ctrl-R history, Ctrl-T files, Alt-C dirs ───
if command -v fzf >/dev/null; then
  export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline
    --color=bg+:0,fg+:15,hl:4,hl+:12,pointer:5,marker:2,prompt:4,info:8,border:8'
  command -v fd >/dev/null && export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git' \
    && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  if [[ ${BLE_VERSION-} ]]; then
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
  else
    eval "$(fzf --bash)"
  fi
fi

# ── Prompt ──────────────────────────────────────────
command -v starship >/dev/null && eval "$(starship init bash)"

[[ ${BLE_VERSION-} ]] && ble-attach
