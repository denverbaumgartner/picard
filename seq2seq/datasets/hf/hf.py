# The goal here is to establish a basic HuggingFace Dataset Schema so that one can simply pass in the dataset and any potential subset of that dataset and proceed to train on it accordingly
import json
import os
from typing import List, Generator, Any, Dict, Tuple
from third_party.spider.preprocess.get_tables import dump_db_json_schema
import datasets

logger = datasets.logging.get_logger(__name__)

_CITATION = """\
    N/A
"""

_DESCRIPTION = """\
A generic dataset loader from the HuggingFace Hub
"""

_HOMEPAGE = ""

_LICENSE = ""

_URL = ""

_LOCATION = "semiotic/spider_dataset_tuning"

_SUBSET = "spider_original"

class HFSource(datasets.GeneratorBasedBuilder):
    VERSION = datasets.Version("1.0.0")

    BUILDER_CONFIGS = [
        datasets.BuilderConfig(
            name=f"HuggingFace Dataset: {_LOCATION}, Subset: {_SUBSET}",
            version=VERSION,
            description=f"A Text-to-SQL Dataset stored on HuggingFace at {_LOCATION}, subsetted by type {_SUBSET}",
        ),
    ]

    def __init__(self, *args, writer_batch_size=None, **kwargs) -> None:
        super().__init__(*args, writer_batch_size=writer_batch_size, **kwargs)
        self.schema_cache = dict()

    def _info(self) -> datasets.DatasetInfo:
        features = datasets.Features(
            {
                "query": datasets.Value("string"),
                "question": datasets.Value("string"),
                "db_id": datasets.Value("string"),
                "db_path": datasets.Value("string"),
                "db_table_names": datasets.features.Sequence(datasets.Value("string")),
                "db_column_names": datasets.features.Sequence(
                    {
                        "table_id": datasets.Value("int32"),
                        "column_name": datasets.Value("string"),
                    }
                ),
                "db_column_types": datasets.features.Sequence(datasets.Value("string")),
                "db_primary_keys": datasets.features.Sequence({"column_id": datasets.Value("int32")}),
                "db_foreign_keys": datasets.features.Sequence(
                    {
                        "column_id": datasets.Value("int32"),
                        "other_column_id": datasets.Value("int32"),
                    }
                ),
            }
        )
        return datasets.DatasetInfo(
            description=_DESCRIPTION,
            features=features,
            supervised_keys=None,
            homepage=_HOMEPAGE,
            license=_LICENSE,
            citation=_CITATION,
        )