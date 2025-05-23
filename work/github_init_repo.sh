#!/bin/bash
echo -e "Please enter your new repository name: \n"
read repo_name
echo -e "Please enter your github username: \n"
read git_user
echo "# $repo_name" >> README.md
# Starting creation #
git init
git add README.md
git commit -m "First commit"
git branch -M main
git remote add origin git@github.com:$git_user/$repo_name.git
git push -u origin main
