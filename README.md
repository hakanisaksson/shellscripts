shellscripts
============

Some useful sysadmin scripts...

* diffdir - run diff recursively to compare two directories
* forgit - run abitrary command for each git repository found
* gitup   - pull all branches that are behind, inspired by git-up
* gitrepo - user friendly script for creating bare git-repositories

diffdir example:
----------------
  Compare all files and subdirs in the current dir with target dir
  and show the differing lines of each file, before asking to update the
  target file:
```shell
# diffdir -r -t /my/target/dir -v -u
```

gitup example:
----------------
```shell
# gitup
   develop              ( up to date )
 * master               ( 1 commits ahead of origin/master )
   tempbranch           ( has no remote on origin )
   testbranch           ( 1 commits behind origin/testbranch )
```

forgit example:
----------------
```shell
$ forgit gitup
for ./ocsinventory/: gitup
* master               ( 5 commits ahead of origin/master )
for ./testrepo/: gitup
* develop              ( up to date )   
  master               ( up to date )
  mingren2             ( has no remote on origin )
for ./verktygsstod/git/: gitup
* master               ( up to date )
```

Install git-prompt.sh
----------------
Save git-prompt-sh as ~/.git-prompt.sh
Add to ~/.bashrc or eqivalent:

```
[ -f  ~/.git-prompt.sh ] && {
  . ~/.git-prompt.sh
  export PS1="[\033[32m\u@\h\033[0m:\033[33m\w\033[0m]\[\033[35m\]\$(__git_ps1)\[\033[0m\]\n# "
}

```
Original source: https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh
