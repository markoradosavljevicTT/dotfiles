#!/bin/bash
set -e

link_dots() {
	local dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	local config_dir="$dotfiles_dir/config"
	local local_dir="$dotfiles_dir/local"

    _link() {
        mkdir -p "$(dirname "$2")"
        [[ -e "$2" && ! -L "$2" ]] && mv "$2" "$2.bak"
        [[ -L "$2" ]] && rm "$2"
        ln -sf "$1" "$2"
    }
    
    if [[ -d "$config_dir" ]]; then
        mkdir -p "$HOME/.config"
        while IFS= read -r -d '' file; do
            _link "$file" "$HOME/.config/${file#$config_dir/}"
        done < <(find "$config_dir" -type f -print0)
    fi
    
    if [[ -d "$local_dir" ]]; then
        mkdir -p "$HOME/.local"
        while IFS= read -r -d '' file; do
            _link "$file" "$HOME/.local/${file#$local_dir/}"
        done < <(find "$local_dir" -type f -print0)
    fi
}

setup_bashrc() {
    local line='[ -f "$HOME/.config/bash/bashrc" ] && source "$HOME/.config/bash/bashrc"'
    while true; do
        printf "Add bash config to:\n1) System (/etc/bash.bashrc)\n2) User (~/.bashrc)\nChoice: "
        read ch
        case $ch in
            1) sudo bash -c "grep -qxF '$line' /etc/bash.bashrc || echo '$line' >> /etc/bash.bashrc"
               echo "Added to /etc/bash.bashrc"; break ;;
            2) grep -qxF "$line" ~/.bashrc 2>/dev/null || echo "$line" >> ~/.bashrc
               echo "Added to ~/.bashrc"; break ;;
            *) echo "Invalid input" ;;
        esac
    done
}

install_packages() {
    local only=${1:-} matched=0
    mkdir -p "$HOME/.local/bin"
    
    local packages=(
        "neovim     neovim/neovim         nvim-linux-x86_64.tar.gz            nvim   nvim"
        "yazi       sxyazi/yazi           x86_64-unknown-linux-musl.zip       zip    yazi"
        "ya         sxyazi/yazi           x86_64-unknown-linux-musl.zip       zip    ya"
        "fzf        junegunn/fzf          linux_amd64.tar.gz                  tar    fzf"
        "fd         sharkdp/fd            x86_64-unknown-linux-musl.tar.gz    tar    fd"
        "ripgrep    BurntSushi/ripgrep    x86_64-unknown-linux-musl.tar.gz    tar    rg"
        "tmux       tmux/tmux-builds      linux-x86_64.tar.gz                 tar    tmux"
    )
    
    _github_url() {
        local repo=$1 pattern=$2 response candidate

        response=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest") || return 1
        while [[ $response == *'"browser_download_url"'* ]]; do
            response=${response#*'"browser_download_url"'}
            response=${response#*:}
            response=${response#*\"}
            candidate=${response%%\"*}
            if [[ $candidate == *"$pattern" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
            response=${response#*\"}
        done

        return 1
    }

    _download() {
        local url=$1 destination=$2

        if command -v curl >/dev/null && curl -fL --retry 3 -o "$destination" "$url"; then
            return 0
        fi
        if command -v wget >/dev/null; then
            wget -O "$destination" "$url"
            return
        fi

        echo "Neither curl nor wget could download $url" >&2
        return 1
    }

    _install_file() {
        local source=$1 binary=$2 destination="$HOME/.local/bin/$2"

        if [[ ! -f $source ]]; then
            echo "Binary '$binary' was not found in the downloaded asset" >&2
            return 1
        fi
        rm -f "$destination"
        cp "$source" "$destination"
        chmod +x "$destination"
    }

    _install_bin() (
        local name=$1 url=$2 binary=$3
        local temp_dir
        temp_dir=$(mktemp -d)
        trap 'rm -rf "$temp_dir"' EXIT
        _download "$url" "$temp_dir/$name"
        _install_file "$temp_dir/$name" "$binary"
    )

    _install_nvim() (
        local name=$1 url=$2 binary=$3
        local temp_dir source source_dir install_dir="$HOME/.local/opt/nvim"
        temp_dir=$(mktemp -d)
        trap 'rm -rf "$temp_dir"' EXIT
        mkdir -p "$temp_dir/extracted" "$(dirname "$install_dir")"
        _download "$url" "$temp_dir/$name.tar.gz"
        tar -xf "$temp_dir/$name.tar.gz" -C "$temp_dir/extracted"
        source=$(find "$temp_dir/extracted" -type f -path "*/bin/$binary" -print -quit)
        source_dir=${source%/bin/$binary}
        if [[ ! -f $source || ! -d $source_dir/share/nvim/runtime ]]; then
            echo "Neovim runtime was not found in the downloaded asset" >&2
            return 1
        fi
        rm -rf "$install_dir"
        mv "$source_dir" "$install_dir"
        rm -f "$HOME/.local/bin/$binary"
        ln -s "$install_dir/bin/$binary" "$HOME/.local/bin/$binary"
    )

    _install_zip() (
        local name=$1 url=$2 binary=$3
        local temp_dir source
        temp_dir=$(mktemp -d)
        trap 'rm -rf "$temp_dir"' EXIT
        _download "$url" "$temp_dir/$name.zip"
        unzip -q "$temp_dir/$name.zip" -d "$temp_dir/extracted"
        source=$(find "$temp_dir/extracted" -type f -name "$binary" -print -quit)
        _install_file "$source" "$binary"
    )

    _install_tar() (
        local name=$1 url=$2 binary=$3
        local temp_dir source
        temp_dir=$(mktemp -d)
        trap 'rm -rf "$temp_dir"' EXIT
        mkdir -p "$temp_dir/extracted"
        _download "$url" "$temp_dir/$name.tar.gz"
        tar -xf "$temp_dir/$name.tar.gz" -C "$temp_dir/extracted"
        source=$(find "$temp_dir/extracted" -type f -name "$binary" -print -quit)
        _install_file "$source" "$binary"
    )

    for pkg in "${packages[@]}"; do
		read -r name repo pattern type binary <<< "$pkg"
		if [[ -n $only && $name != "$only" ]]; then
			continue
		fi
		matched=1
        
        echo "Installing $name..."
        if ! url=$(_github_url "$repo" "$pattern"); then
            echo "Failed to get URL for $name"
            continue
        fi
        echo "URL: $url"
        case $type in
            bin) _install_bin "$name" "$url" "$binary" ;;
            nvim) _install_nvim "$name" "$url" "$binary" ;;
            zip) _install_zip "$name" "$url" "$binary" ;;
            tar) _install_tar "$name" "$url" "$binary" ;;
        esac
        echo "$name installed"
    done

    if [[ -n $only && $matched -eq 0 ]]; then
        echo "Unknown package: $only" >&2
        return 1
    fi
}

case "${1:-all}" in
	dots) link_dots ;;
    bash) setup_bashrc ;;
	packages) install_packages "${2:-}" ;;
    all) link_dots; setup_bashrc; install_packages ;;
    *) echo "Usage: $0 [dots|bash|packages|all]"; exit 1 ;;
esac
