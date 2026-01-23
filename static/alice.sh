#!/bin/bash

# VARIABLES

aur_helper="yay"
dotfiles_repository="https://github.com/alva-v/dotfiles.git"
whiptail_title="Alice"
programs_file="$(dirname "$0")/programs.csv"
tmp_programs_file="/tmp/alice-programs.csv"
username=$(logname)
repodir="/home/$username/.local/src"
log_dir="/home/$username/.local/state/alice"

# FUNCTIONS

check_consent() {
    if ! whiptail --title "$whiptail_title" --yesno "You are about to start Alva's Autorice (Alice) script, are you sure?" --defaultno  0 0; then
        clear
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
    echo "Installing \`$aur_helper\` AUR helper..."
    pacman --query --quiet "$aur_helper" > /dev/null 2>&1 && return 0 # Return if already installed
    runuser -u "$username" -- mkdir --parents "$repodir"
    runuser -u "$username" -- mkdir "$install_dir" > /dev/null 2>&1
    runuser -u "$username" -- git -C "$repodir" clone --depth 1 --single-branch --no-tags --quiet \
        "https://aur.archlinux.org/$aur_helper.git" "$install_dir" > /dev/null || 
        {
            pushd "$install_dir" > /dev/null || return 1
            runuser -u "$username" -- git pull --force origin master > /dev/null
            popd > /dev/null || return 1
        }
    pushd "$install_dir" > /dev/null || return 1
    runuser -u "$username" -- makepkg --noconfirm --syncdeps --install > /dev/null 2>&1
    popd > /dev/null || return 1
}

install_aur_package() {
    package="$1"
    echo "$aur_installed" | grep --quiet "^$package$" && return 0
    runuser -u "$username" -- "$aur_helper" -S --noconfirm "$package" > /dev/null 2>&1 || return 1
}

install_base() {
    echo "Installing softwares needed for the rest of the script to work..."
    for x in curl ca-certificates base-devel git ntp bc; do
        echo "Installing \`$x\`"
        install_package "$x"
    done
}

install_dotfiles() {
    folder="/home/$username/.dotfiles"
    echo "Downloading and installing dotfiles in code folder..."
    if ! git -C "$folder" status > /dev/null 2>&1;then # Create git dir if missing
        [ ! -d "$folder" ] && sudo -u "$username" mkdir -p "$folder"
        sudo -u "$username" git clone "$dotfiles_repository" "$folder"
    fi
    sudo -u "$username" bash "$folder/bootstrap.sh"
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
        runuser -u "$username" -- mkdir -p "$log_dir"
        echo "${failed_installs[*]}" > "$log_dir/failed_installs"
        return 1
    fi
}

refresh() {
    echo "Refreshing Pacman databases..."
    pacman --noconfirm --sync --refresh --refresh > /dev/null 2>&1
    echo "Refreshing keyrings..."
    pacman --noconfirm --sync archlinux-keyring > /dev/null 2>&1
}

# Set a temporary auto deleting sudoers file
set_sudoers() {
    tmp_sudoers="/etc/sudoers.d/99-alice-tmp"
    trap 'rm -f $tmp_sudoers' HUP INT QUIT TERM PWR EXIT
    # Heredoc with <<- must be kept indented with tabs, not spaces
    cat <<-EOF > "$tmp_sudoers"
		$username ALL=(ALL:ALL) NOPASSWD: ALL
		Defaults:%wheel,root runcwd=*
	EOF
    chmod 440 "$tmp_sudoers"
}

sync_time() {
    echo "Syncing system time..."
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
runuser -u "$username" -- "$aur_helper" --yay --save --devel
install_listed_packages || error "Error installing packages"
install_dotfiles || error "Error installing dotfiles"
cleanup
echo "Alice is done, enjoy!"