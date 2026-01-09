#!/bin/bash

# VARIABLES

aur_helper="yay"
dotfiles_repository="https://github.com/alva-v/dotfiles.git"
infobox_title="Alice"
programs_file="$(dirname "$0")/programs.csv"
tmp_programs_file="/tmp/alice-programs.csv"
username=$(logname)
repodir="/home/$username/.local/src"
log_dir="/home/$username/.local/state/alice"

# FUNCTIONS

check_consent() {
    if ! whiptail --title "$infobox_title" --yesno "You are about to start Alva's Autorice (Alice) script, are you sure?" --defaultno  0 0; then
        exit 1
    fi
    clear
}

check_internet() {
    if ! curl -s --max-time 5 --head cloudflare.com > /dev/null 2>&1; then
        return 1
    fi

}

check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        return 1
    fi
}

cleanup() {
    rm -f /etc/sudoers.d/alice-temp
}

configure_makepkg() {
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
}

error() {
    printf "%s\n" "$1" >&2
    exit 1
}

install_aur_helper() {
    install_dir="$repodir/$aur_helper"
    whiptail --title "$infobox_title" --infobox "Installing \`$aur_helper\` AUR helper..." 7 40
    pacman --query --quiet "$aur_helper" > /dev/null 2>&1 && return 0 # Return if already installed
    mkdir --parents "$repodir"
    chown -R "$username":wheel "$(dirname "$repodir")"
    sudo --user="$username" mkdir "$install_dir" > /dev/null 2>&1
    sudo --user="$username" git -C "$repodir" clone --depth 1 --single-branch --no-tags --quiet \
        "https://aur.archlinux.org/$aur_helper.git" "$install_dir" > /dev/null || 
        {
            pushd "$install_dir" > /dev/null || return 1
            sudo --user="$username" git pull --force origin master > /dev/null
            popd > /dev/null || return 1
        }
    pushd "$install_dir" > /dev/null || return 1
    sudo --user="$username" makepkg --noconfirm --syncdeps --install > /dev/null 2>&1
    popd > /dev/null || return 1
}

install_aur_package() {
    package="$1"
    echo "$aur_installed" | grep --quiet "^$package$" && return 0
    sudo --user="$username" "$aur_helper" -S --noconfirm "$package" > /dev/null 2>&1 || return 1
}

install_base() {
    for x in curl ca-certificates base-devel git ntp zsh dash bc; do
        whiptail --title "$infobox_title" \
            --infobox "Installing \`$x\` which is needed for the rest of the script to work" 8 70
        install_package "$x"
    done
}

install_dotfiles() {
    folder="/home/$username/.dotfiles"
    whiptail --title "$infobox_title" --infobox "Downloading and installing dotfiles in code folder..." 7 60
    if ! git -C "$folder" status > /dev/null 2>&1;then # Create git dir if missing
        [ ! -d "$folder" ] && sudo -u "$username" mkdir -p "$folder"
        sudo -u "$username" git -C "$folder" clone "$dotfiles_repository"
    fi
    bash "$folder/bootstrap.sh"
}

install_package() {
    local package="${1}"
    pacman --noconfirm --sync --needed "$package" > /dev/null 2>&1 || return 1

}

install_listed_packages() {
    ([ -f "$programs_file" ] && cp "$programs_file" "$tmp_programs_file") ||
        curl --location --silent "$programs_file"
    sed -i "/^#/d" "$tmp_programs_file"
    total=$(wc -l < "$tmp_programs_file")
    aur_installed=$(pacman --query --quiet --foreign)
    clear
    while IFS=, read -r tag program comment; do
        n=$((n + 1))
        percentage=$(bc -l <<< "$n/$total*100")
        printf "Installing package %s/%s (%s%%): %s\n" "$n" "$total" "${percentage%%.*}" "$program"
        case "$tag" in
            "A") install_aur_package "$program" || failed_installs+=("$program");;
            *) install_package "$program" || failed_installs+=("$program");;
        esac
    done < "$tmp_programs_file"
    if [[ ${#failed_installs[@]} != 0 ]]; then
        failed_log="$log_dir/failed_installs"
        echo "Some programs could not be installed, see log in $failed_log"
        mkdir -p "$log_dir"
        echo "${failed_installs[*]}" > "$log_dir/failed_installs"
        return 1
    fi
}

refresh() {
    whiptail --title "$infobox_title" --infobox "Refreshing Pacman databases..." 7 40
    pacman --noconfirm --sync --refresh --refresh > /dev/null 2>&1
    whiptail --title "$infobox_title" --infobox "Refreshing keyrings..." 7 40
    pacman --noconfirm --sync archlinux-keyring > /dev/null 2>&1
}

# Set a temporary auto deleting sudoers file
set_sudoers() {
    tmp_sudoers="/etc/sudoers.d/alice-tmp"
    trap 'rm -f $tmp_sudoers' HUP INT QUIT TERM PWR EXIT
    # Heredoc with <<- must be kept indented with tabs, not spaces
    cat <<-EOF > "$tmp_sudoers"
		%wheel ALL=(ALL:ALL) NOPASSWD: ALL
		Defaults:%wheel,root runcwd=*
	EOF
    chmod 440 "$tmp_sudoers"
}

sync_time() {
    whiptail --title "$infobox_title" --infobox "Syncing the system time..." 7 40
    ntpd --quit --panicgate > /dev/null 2>&1
}

# SCRIPT

check_privileges || error "Please run this script with root privileges (sudo)"
check_internet || error "Please connect to the internet before running this script"
check_consent || error "User exited"
refresh || error "Error refreshing Arch keyrings"
install_base || error "Error installing base packages"
sync_time || error "Error syncing the system time"
set_sudoers || error "Error disabling passwords for sudo usage"
configure_makepkg
install_aur_helper || error "Error installing AUR helper"
sudo --user="$username" "$aur_helper" --yay --save --devel
install_listed_packages || error "Error installing packages"
install_dotfiles || error "Error installing dotfiles"
cleanup