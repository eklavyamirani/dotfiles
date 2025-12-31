### To use the config on an existing system
Update the submodule. ```git submodule update --remote --merge```
Commit
Use diff to compare the files between local and the git repo.
Since symlinks aren't set correctly, we need to restow. 
```stow -R -t ~/ -n -v .```
Remove the current files on the host
Run the stow command without -n.
