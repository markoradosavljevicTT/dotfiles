#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"
LOCAL_DIR="$DOTFILES_DIR/local"

link_files() {
    local src_dir=$1
    local target_base=$2

    if [[ ! -d "$src_dir" ]]; then
        return 1
    fi

    mkdir -p "$target_base"

    while IFS= read -r -d '' file; do
        rel_path="${file#$src_dir/}"
        target="$target_base/$rel_path"
        target_parent=$(dirname "$target")

        if [[ -f "$file" ]]; then
            mkdir -p "$target_parent"

            if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                mv "$target" "$target.bak"
            fi

            if [[ -L "$target" ]]; then
                rm "$target"
            fi

            ln -sf "$file" "$target"
        fi
    done < <(find "$src_dir" -type f -print0)
}

BASHRC_SOURCE='source "$HOME/.config/bash/bashrc"'

add_source_if_missing() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    touch "$file"

    if ! grep -Fxq "$BASHRC_SOURCE" "$file"; then
        echo "$BASHRC_SOURCE" >> "$file"
    fi
}

link_files "$CONFIG_DIR" "$HOME/.config"
link_files "$LOCAL_DIR" "$HOME/.local"

add_source_if_missing "$HOME/.bash_profile"
add_source_if_missing "$HOME/.bashrc"
