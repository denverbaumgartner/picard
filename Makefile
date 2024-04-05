# GIT_HEAD_REF := $(shell git rev-parse HEAD)
GIT_HEAD_REF := d3d1fd95713f3b9616745c737ee5b696a4c09f8b

BASE_IMAGE := pytorch/pytorch:1.9.0-cuda11.1-cudnn8-devel

DEV_IMAGE_NAME := text-to-sql-dev
TRAIN_IMAGE_NAME := text-to-sql-train
EVAL_IMAGE_NAME := text-to-sql-eval

BUILDKIT_IMAGE := tscholak/text-to-sql-buildkit:buildx-stable-1
BUILDKIT_BUILDER ?= buildx-local
BASE_DIR := $(shell pwd)

BASE_REPO_OWNER := denverbaumgartner
BASE_REPO_KEY := /home/ubuntu/snap/gh/502/.ssh/id_ed25519

.PHONY: init-buildkit
init-buildkit:
	docker buildx create \
		--name buildx-local \
		--driver docker-container \
		--driver-opt image=$(BUILDKIT_IMAGE),network=host \
		--use

.PHONY: del-buildkit
del-buildkit:
	docker buildx rm buildx-local

.PHONY: build-thrift-code
build-thrift-code:
	thrift1 --gen mstch_cpp2 picard.thrift
	thrift1 --gen mstch_py3 picard.thrift
	cd gen-py3 && python setup.py build_ext --inplace

.PHONY: build-picard-deps
build-picard-deps:
	cabal update
	thrift-compiler --hs --use-hash-map --use-hash-set --gen-prefix gen-hs -o . picard.thrift
	patch -p 1 -N -d third_party/hsthrift < ./fb-util-cabal.patch || true
	cd third_party/hsthrift \
		&& make THRIFT_COMPILE=thrift-compiler thrift-cpp thrift-hs
	cabal build --only-dependencies lib:picard

.PHONY: build-picard
build-picard:
	cabal install --overwrite-policy=always --install-method=copy exe:picard

.PHONY: build-dev-image
build-dev-image:
	ssh-add
	docker buildx build --no-cache \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(DEV_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(DEV_IMAGE_NAME):cache \
		--tag tscholak/$(DEV_IMAGE_NAME):devcontainer \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target dev \
		--cache-from type=registry,ref=tscholak/$(DEV_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:$(BASE_REPO_OWNER)/picard#$(GIT_HEAD_REF)

.PHONY: pull-dev-image
pull-dev-image:
	docker pull tscholak/$(DEV_IMAGE_NAME):$(GIT_HEAD_REF)
 
.PHONY: build-train-image
build-train-image:
	eval $$(ssh-agent -s) && ssh-add $(BASE_REPO_KEY) && \
	docker buildx build --no-cache \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(TRAIN_IMAGE_NAME):cache \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target train \
		--cache-from type=registry,ref=tscholak/$(TRAIN_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:$(BASE_REPO_OWNER)/picard#$(GIT_HEAD_REF)

.PHONY: pull-train-image
pull-train-image:
	docker pull tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF)

.PHONY: build-eval-image
build-eval-image:
	ssh-add
	docker buildx build  --no-cache \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(EVAL_IMAGE_NAME):cache \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target eval \
		--cache-from type=registry,ref=tscholak/$(EVAL_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:$(BASE_REPO_OWNER)/picard#$(GIT_HEAD_REF)

.PHONY: pull-eval-image
pull-eval-image:
	docker pull tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF)

.PHONY: train
train: pull-train-image
	mkdir -p -m 777 train
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/train,target=/train \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train.json"
# tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF) "\"
# d3d1fd95713f3b9616745c737ee5b696a4c09f8b
# tscholak/$(TRAIN_IMAGE_NAME):d3d1fd95713f3b9616745c737ee5b696a4c09f8b "\"
.PHONY: train_cosql
train_cosql: pull-train-image
	mkdir -p -m 777 train
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/train,target=/train \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train_cosql.json"

.PHONY: eval
eval: pull-eval-image
	mkdir -p -m 777 eval
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/eval,target=/eval \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/eval.json"

.PHONY: eval_cosql
eval_cosql: pull-eval-image
	mkdir -p -m 777 eval
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/eval,target=/eval \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/eval_cosql.json"

.PHONY: serve
serve: pull-eval-image
	mkdir -p -m 777 database
	mkdir -p -m 777 transformers_cache
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		-p 8000:8000 \
		--mount type=bind,source=$(BASE_DIR)/database,target=/database \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/serve_seq2seq.py configs/serve.json"

.PHONY: prediction_output
prediction_output: pull-eval-image
	mkdir -p -m 777 prediction_output
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		-p 8000:8000 \
		--mount type=bind,source=$(BASE_DIR)/prediction_output,target=/prediction_output \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		/bin/bash -c "python seq2seq/prediction_output.py configs/prediction_output.json"


################ 
# Local Builds #
################

.PHONY: build_local
build_local:
	docker build -t local:latest .

.PHONY: build_local_reproduce
build_local_reproduce:
	docker build -t local:reproduce .

.PHONY: build_local_test
build_local_test:
	docker build -t local:test .

.PHONY: run_local_test
run_local_test:
	mkdir -p -m 777 train_test
	mkdir -p -m 777 transformers_cache_test
	mkdir -p -m 777 wandb
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train_test,target=/train_test \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache_test,target=/transformers_cache_test \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:test \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train_test.json"

.PHONY: run_local_subset
run_local_subset:
	mkdir -p -m 777 train_subset
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train_subset,target=/train_subset \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:latest \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train_subset.json"
		
.PHONY: run_local
run_local:
	mkdir -p -m 777 train
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train,target=/train \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:latest \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train.json"

.PHONY: run_local_reproduce
run_local_reproduce:
	mkdir -p -m 777 train_reproduce
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train_reproduce,target=/train_reproduce \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:reproduce \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train_reproduce.json"

.PHONY: run_local_clear
run_local_clear:
	mkdir -p -m 777 train_full_clear_cache
	mkdir -p -m 777 transformers_cache_clear
	mkdir -p -m 777 wandb_clear_cache
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train_full_clear_cache,target=/train_full_clear_cache \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache_clear,target=/transformers_cache_clear \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb_clear_cache,target=/app/wandb_clear_cache \
		local:latest \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/train_clear_cache.json"

.PHONY: eval_local
eval_local:
	mkdir -p -m 777 eval
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/eval,target=/eval \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:latest \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/eval_local.json"

.PHONY: eval_local_reproduce
eval_local_reproduce:
	mkdir -p -m 777 eval
	mkdir -p -m 777 transformers_cache
	mkdir -p -m 777 wandb
	docker run \
		-it \
		--rm \
		--user 13011:13011 \
		--mount type=bind,source=$(BASE_DIR)/eval,target=/eval \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache,target=/transformers_cache \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:reproduce \
		/bin/bash -c "python seq2seq/run_seq2seq.py configs/eval_local.json"

.PHONY: run_local_data
run_local_data:
	mkdir -p -m 777 train_data
	mkdir -p -m 777 transformers_cache_test
	mkdir -p -m 777 wandb
	docker run -it \
		--mount type=bind,source=$(BASE_DIR)/train_data,target=/train_data \
		--mount type=bind,source=$(BASE_DIR)/transformers_cache_test,target=/transformers_cache_test \
		--mount type=bind,source=$(BASE_DIR)/configs,target=/app/configs \
		--mount type=bind,source=$(BASE_DIR)/wandb,target=/app/wandb \
		local:latest \
		/bin/bash -c "python seq2seq/load_data.py configs/train_data.json"