#!/usr/bin/xonsh

import contextlib
import os

# $RAISE_SUBPROC_ERROR = True

WORKSPACE = $PWD
DIR = os.path.join(WORKSPACE, 'tmp')
installed = set()
sudo pacman -Sy


@contextlib.contextmanager
def yay_guard():
    """yay uses $ARGS, we must delete it temporarily to avoid collision"""
    save = $ARGS
    del $ARGS
    yield
    $ARGS = save


@contextlib.contextmanager
def enter_once(directory):
    """enter a directory, when done, delete it"""
    save = $PWD
    mkdir -p @(directory)
    cd @(directory)
    yield
    cd @(save)
    rm -rf @(directory)


def list_packages():
    l = $(ls *.pkg.tar.zst).strip().split()
    result = set()
    for p in l:
        try:
            i = len(p)
            for _ in range(3):
                i -= 1
                while p[i] != '-':
                    i -= 1
            result.add(p[:i])
        except IndexError:
            pass
    return result


def yay_package(pkgname, stack):
    print(f"==> Building {pkgname}")
    with yay_guard():
        yay -G @(pkgname)

    with enter_once(pkgname):
        yay_deps('PKGBUILD', stack)
        if pkgname in installed:
            return
        makepkg -s --noconfirm
        sudo pacman -U --noconfirm *.pkg.*
        cp *.pkg.* @(DIR)
        for p in list_packages():
            installed.add(p)


def yay_deps(filename, stack):
    deps=$(makepkg -p @(filename) --printsrcinfo | awk '{$1=$1};1' | grep -oP '(?<=^depends = ).*')
    for d in deps.strip().split():
        blacklist = ['>=', '>', '<=', '<', '==']
        for b in blacklist:
            if b in d:
                d = d.split(b)[0]
        d = d.strip()
	print("d: {},\n installed: {},\n stack: {}\n".format(d, installed, stack))
        if $(sh -c @(f"pacman -Ss ^{d}$ || true")).strip() == "" and d not in installed and d not in stack:
            print(f"==> Recursively building {d}")
            stack.add(d)
            yay_package(d, stack)


def make_top_level_package(pkgname):
    print(f"==> Building {pkgname}")
    cp -r @(f"{WORKSPACE}/{pkgname}") @(pkgname)
    rev = $(git rev-list --count HEAD).strip()
    with enter_once(pkgname):
        sed -i @(f's/^pkgver=.*$/pkgver={rev}/g') PKGBUILD
        makepkg -d -f
        rm -rf pkg src
        cp *.pkg.* @(DIR)
        yay_deps('PKGBUILD', set())


def upload():
    git init
    git remote add origin git@github.com:chendscm/packages.git
    git checkout --orphan gh-pages
    git add .
    git status
    git commit -m "update"
    git push --force -u origin gh-pages


with enter_once(DIR):
    print(f"==> Generating packages at {DIR}")

    make_top_level_package("basic")
    make_top_level_package("desktop")

    repo-add chendsystem.db.tar.gz *.pkg.*
    tree -H '.' -L 1 --noreport --charset utf-8 > index.html

    ls -lah

    upload()
