# ~/.zshrc

export PATH="$HOME/.npm-global/bin:$PATH"
export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:/home/azriel/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# ── Kitty shell integration (manual: kitty launches zsh via an sh wrapper) ──
if [[ -n $KITTY_INSTALLATION_DIR ]]; then
  export KITTY_SHELL_INTEGRATION="enabled"
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi

# ── History ─────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history extended_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks
setopt autocd interactive_comments no_beep

# ── Completion ──────────────────────────────────────
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit -d ~/.cache/zcompdump
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls $realpath'
zstyle ':fzf-tab:*' fzf-flags --height=40% --border=rounded
zstyle ':fzf-tab:*' switch-group '<' '>'

# ── Keys (emacs mode) ───────────────────────────────
bindkey -e
bindkey '^[[1;5D' backward-word      # Ctrl-Left
bindkey '^[[1;5C' forward-word       # Ctrl-Right
bindkey '^[[H'    beginning-of-line  # Home
bindkey '^[[F'    end-of-line        # End
bindkey '^[[3~'   delete-char        # Delete
bindkey '^H'      backward-kill-word # Ctrl-Backspace

# ── Plugins (pacman/AUR, skipped if missing) ────────
_zplug() { [[ -r $1 ]] && source "$1" }
for _p in /usr/share/zsh/plugins/fzf-tab*/fzf-tab.plugin.zsh(N); do _zplug $_p; break; done
_zplug /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
_zplug /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
unset _p

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=30
ZSH_AUTOSUGGEST_USE_ASYNC=1
bindkey '^ ' autosuggest-accept      # Ctrl-Space accepts suggestion (Right/End also work)
if (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up    # Up: history matching what's typed
  bindkey '^[[B' history-substring-search-down
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='fg=4,bold'
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='fg=1,bold'
fi

# ── Modern CLI replacements (only if installed) ─────
alias grep='grep --color=auto'
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -l --icons=auto --git --group-directories-first'
  alias la='eza -la --icons=auto --git --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto'
else
  alias ls='ls --color=auto'
fi
(( $+commands[bat] )) && alias cat='bat --paging=never --style=plain'
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"

# ── Kitty kittens ───────────────────────────────────
if [[ $TERM == xterm-kitty ]]; then
  alias icat='kitten icat'
  alias kssh='kitten ssh'
  alias kdiff='kitten diff'
fi

# ── fzf: Ctrl-T files, Alt-C dirs (Ctrl-R handed to atuin below) ──
if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline
    --color=bg+:0,fg+:15,hl:4,hl+:12,pointer:5,marker:2,prompt:4,info:8,border:8'
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  source <(fzf --zsh)
fi

# ── atuin: Ctrl-R history search; also feeds autosuggestions ──
(( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)"

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

# ── Prompt ──────────────────────────────────────────
(( $+commands[starship] )) && eval "$(starship init zsh)"

# ── Syntax highlighting (must load last) ────────────
_zplug /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=4'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=5'
ZSH_HIGHLIGHT_STYLES[alias]='fg=6'
ZSH_HIGHLIGHT_STYLES[function]='fg=6'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=5,bold'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=1,bold'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=2'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=2'
ZSH_HIGHLIGHT_STYLES[path]='fg=4,underline'
ZSH_HIGHLIGHT_STYLES[comment]='fg=8'
unfunction _zplug
