export PS1='%n@%m %1~ %# '
alias nvim-kickstart="NVIM_APPNAME=nvim-kickstart; nvim"
export NVIM_APPNAME=nvim

alias ls="ls -a"
alias custom_dockerlast="docker ps -lq"

# custom helper functions
my-add-path-directory() {
    if [[ -d "$1" ]]; then
        export PATH="$1:$PATH"
        echo "Added $1 to PATH"
    else
        echo "$1 is not a valid directory"
    fi
}
