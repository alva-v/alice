# Alice

Alice (**Al**va's Autor**ice**) is a script to automatically set up an i3 desktop environnement catering to my needs.

## Prerequisites

- A fresh Arch Linux installation
- Internet connection
- Root access
- See the [Dotfiles README](https://github.com/alva-v/dotfiles/blob/main/Readme.md) before running

## Usage

```bash
sudo bash static/alice.sh
```

## Adding Packages

Edit `static/programs.csv`. Format: `TAG, NAME, COMMENT`

- Empty TAG → installed via Pacman
- `A` → installed via AUR (yay)
