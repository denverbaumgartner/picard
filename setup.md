ensure you have ssh access to the github account defined in the `Makefile`: `BASE_REPO_OWNER`

you can set this up on a remote machine using `gh auth login`

you will see your key at the end being stored in a fashion similar to: `/home/ubuntu/snap/gh/502/.ssh/id_ed25519`

you then need to setup the ssh-agent
```bash
eval $(ssh-agent)
ssh-add /home/ubuntu/snap/gh/502/.ssh/id_ed25519
```

building the training image: 
```bash
make init-buildkit
sudo make build-train-image
```