# Set up logging
import sys
import logging

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
    datefmt="%m/%d/%Y %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
    level=logging.WARNING,
)
logger = logging.getLogger(__name__)

import os
import json
import pandas as pd
from pathlib import Path
from contextlib import nullcontext
from dataclasses import asdict, fields
from transformers.hf_argparser import HfArgumentParser
from transformers.training_args_seq2seq import Seq2SeqTrainingArguments
from transformers.models.auto import AutoConfig, AutoTokenizer, AutoModelForSeq2SeqLM
from transformers.data.data_collator import DataCollatorForSeq2Seq
from transformers.trainer_utils import get_last_checkpoint, set_seed
from transformers.models.t5.modeling_t5 import T5ForConditionalGeneration
from transformers.models.t5.tokenization_t5_fast import T5TokenizerFast
from transformers.tokenization_utils_fast import PreTrainedTokenizerFast
from tokenizers import AddedToken
from seq2seq.utils.args import ModelArguments
from seq2seq.utils.picard_model_wrapper import PicardArguments, PicardLauncher, with_picard
from seq2seq.utils.dataset import DataTrainingArguments, DataArguments
from seq2seq.utils.dataset_loader import load_dataset
from seq2seq.utils.spider import SpiderTrainer
from seq2seq.utils.cosql import CoSQLTrainer

def main() -> None:
    # See all possible arguments by passing the --help flag to this script.
    parser = HfArgumentParser(
        (PicardArguments, ModelArguments, DataArguments, DataTrainingArguments, Seq2SeqTrainingArguments)
    )
    picard_args: PicardArguments
    model_args: ModelArguments
    data_args: DataArguments
    data_training_args: DataTrainingArguments
    training_args: Seq2SeqTrainingArguments
    if len(sys.argv) == 2 and sys.argv[1].endswith(".json"):
        # If we pass only one argument to the script and it's the path to a json file,
        # let's parse it to get our arguments.
        picard_args, model_args, data_args, data_training_args, training_args = parser.parse_json_file(
            json_file=os.path.abspath(sys.argv[1])
        )
    elif len(sys.argv) == 3 and sys.argv[1].startswith("--local_rank") and sys.argv[2].endswith(".json"):
        data = json.loads(Path(os.path.abspath(sys.argv[2])).read_text())
        data.update({"local_rank": int(sys.argv[1].split("=")[1])})
        picard_args, model_args, data_args, data_training_args, training_args = parser.parse_dict(args=data)
    else:
        picard_args, model_args, data_args, data_training_args, training_args = parser.parse_args_into_dataclasses()

    # Initialize tokenizer
    tokenizer = AutoTokenizer.from_pretrained(
        model_args.tokenizer_name if model_args.tokenizer_name else model_args.model_name_or_path,
        cache_dir=model_args.cache_dir,
        use_fast=model_args.use_fast_tokenizer,
        revision=model_args.model_revision,
        use_auth_token=True if model_args.use_auth_token else None,
    )
    assert isinstance(tokenizer, PreTrainedTokenizerFast), "Only fast tokenizers are currently supported"
    if isinstance(tokenizer, T5TokenizerFast):
        # In T5 `<` is OOV, see https://github.com/google-research/language/blob/master/language/nqg/tasks/spider/restore_oov.py
        tokenizer.add_tokens([AddedToken(" <="), AddedToken(" <")])

    # Load dataset
    metric, dataset_splits = load_dataset(
        data_args=data_args,
        model_args=model_args,
        data_training_args=data_training_args,
        training_args=training_args,
        tokenizer=tokenizer,
    )

    write_path = training_args.output_dir + '/train_data.csv'
    print(write_path)
    #train_df = dataset_splits.train_split.dataset.to_csv(write_path)

    #df = dataset_splits.train_split.dataset.to_pandas()
    def add_input_text(example):
        decoded_text = tokenizer.decode(example['input_ids'], skip_special_tokens=True)
        example['input_text'] = decoded_text
        return example

    data = dataset_splits.train_split.dataset
    updated_data = data.map(add_input_text)
    updated_data.to_csv(write_path)

    # Decode the input_ids back to text
    # decoded_texts = []
    # for index, row in df.iterrows():
    #     input_ids = eval(row['input_ids'])  # Convert the string representation of the list back to a list
    #     decoded_text = tokenizer.decode(input_ids, skip_special_tokens=True)  # Decode the input IDs
    #     decoded_texts.append(decoded_text)

    # # Add the decoded texts to the DataFrame
    # df['decoded_text'] = decoded_texts
    # df.to_csv(write_path)
    

if __name__ == "__main__":
    main()