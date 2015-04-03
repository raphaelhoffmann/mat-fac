# Tutorial: Text Similarity and Clustering 

There are many situations in which we would like to measure the
semantic similarity of two snippets of text. A few examples are:

* *Gaining corpus overview*: Given a new collection of documents, one is often interested
  in getting an overview of what types of documents are contained in the collection. Clustering
  similar documents can give us such an overview.
* *Finding examples for extractor development*: Developing extractors
  often requires finding examples to inform new rules for distant supervision or
  features. Showing sentences without extractions but which are most similar to
  those with extractions helps us find recall errors and improve extractors.
* *Enhancing extraction with latent types as features*: Type information can
  dramatically improve the quality of an extractor, but typical named-entity taggers
  capture only a handful of types. We can add latent type information by clustering 
  words or phrases (with context they appear in), and adding features that indicate
  cluster membership.
* *Linking entities with an incomplete database*: For many entity linking tasks we only have partial databases. For example, 
  there is no database that contains all persons or organizations in the world. When mentions
  cannot be linked to a database it is often still useful to cluster them. 

In this tutorial, we develop a system that estimates the semantic similarity of
documents and both, finds the nearest neighbors to any given document, and
creates a global clustering of documents.

We use the [Reuters-21578 dataset](http://archive.ics.uci.edu/ml/machine-learning-databases/reuters21578-mld/reuters21578.html),
which contains 20,000 articles that appeared on the Reuters newswire in 1987.
These articles cover a wide variety of topics, including political events,
natural desasters, and business news. 

This tutorial assumes that you are already familiar with setting up and running deepdive applications.

## Installing MADlib

Several of the steps in this tutorial require [MADlib](http://madlib.net/), an extension to Postgres and Greenplum
that offers a library of machine learning algorithms. Please follow the instructions in the [installation guide](https://github.com/madlib/madlib/wiki/Installation-Guide)
to set up MADlib on your machine.

## Preparing the Reuters dataset

We download the Reuters corpus from [UC Irvine repository](http://archive.ics.uci.edu/ml/machine-learning-databases/reuters21578-mld/reuters21578.html).
The original data is in SGML which we convert to JSON for readability and CSV for loading into the database. The following scripts perform these steps:

    script/fetch-reuters.py
    script/get-reuters-json-csv.py

Next, we create a schema for articles in the database and load the data. Both can be done by running:

    script/load-reuters.py

The articles are stored as strings of text. To more easily design features for document similarity we would like to compute
token boundaries by running a tokenizer. Deepdive offers the
`nlp_extractor` for that. We can run the `nlp_extractor` on the command line or as an extraction
step in our deepdive application. We opt for the latter and add the following extractor to `application.conf`:

```
extract_preprocess: {
  style: json_extractor
  before: psql -h ${PGHOST} -p ${PGPORT} -d ${DBNAME} -f ${APP_HOME}/schemas/sentences.sql
  input: """
         SELECT id,
           body
         FROM articles
         WHERE NOT BODY IS NULL
         ORDER BY id ASC
         """
  output_relation: sentences
  udf: ${DEEPDIVE_HOME}/examples/nlp_extractor/run.sh -k id -v body -l 100 -a "tokenize,ssplit,pos"
}
```

Note: We set `nlp_extractor` to only run its tokenize, ssplit, and pos annotators. We do not run the
parse annotator (which would normally be included), since we don't need parses and parsing requires
many hours of computation time on this corpus.

The output is now by sentence. To simplify working with the data in the following sections, we group
tokens by document:

```
extract_document_tokens: {
  style: sql_extractor
  sql: """DROP TABLE IF EXISTS article_tokens;
          CREATE TABLE article_tokens (id int, words text[]);
          CREATE AGGREGATE array_accum (anyarray)
          (
            sfunc = array_cat,
            stype = anyarray,
            initcond = '{}'
          ); 
          INSERT INTO article_tokens 
            SELECT cast(substring(sentence_id from '^[^@]+') as int), 
                   array_accum(words) 
            FROM sentences GROUP BY substring(sentence_id from '^[^@]+');
       """
}
```


## Text Similarity


Plan: represent each document as a vector of features.
compare documents by comparing their vectors.
Features: bag of words
experiment with phrases (?)


Most entries 0 --> sparse vector representation.

Need encoding of documents as sparse vectors,
as input to madlib


1. write extractor for words and their positions, 

   doc_id, term, positions 

```sql
SELECT madlib.svec_sfv((SELECT a FROM features LIMIT 1),b)::float8[]
         FROM article_tokens;
```



2. prepare dictionary table: (just a sql query)?

3. generate sparse vectors

SELECT * FROM madlib.gen_doc_svecs('svec_output', 'dictionary_table', 'id', 'term',
                            'documents_table', 'id', 'term', 'positions');

4. anlyze the sparse vecs:
SELECT * FROM svec_output ORDER by doc_id;

now can measure document similarity by cosine distance.
todo

two problems:
1. stopwords, 



SELECT madlib.svec_sfv((SELECT a FROM features LIMIT 1),b)::float8[]
         FROM documents;

lining up with original text
SELECT madlib.svec_sfv((SELECT a FROM features LIMIT 1),b)::float8[]
                , b
         FROM documents;

compute the cosine distance 

```sql
SELECT docnum,
                180. * ( ACOS( madlib.svec_dmin( 1., madlib.svec_dot(tf_idf, testdoc)
                    / (madlib.svec_l2norm(tf_idf)*madlib.svec_l2norm(testdoc))))/3.141592654) angular_distance
         FROM weights,(SELECT tf_idf testdoc FROM weights WHERE docnum = 1 LIMIT 1) foo
         ORDER BY 1;
```

For more information on how to encode sparse vectors and compute cosine distance with MADlib, see [this documentation page](http://doc.madlib.net/latest/group__grp__svec.html).

## TF/IDF feature weighting

Problem:

example why we want to weight features differently.


tfidf

{#Times in document} * log {#Documents / #Documents the term appears in}.

CREATE TABLE corpus AS
            (SELECT a, madlib.svec_sfv((SELECT a FROM features LIMIT 1),b) sfv
         FROM documents);
CREATE TABLE weights AS
          (SELECT a docnum, madlib.svec_mult(sfv, logidf) tf_idf
           FROM (SELECT madlib.svec_log(madlib.svec_div(count(sfv)::madlib.svec,madlib.svec_count_nonzero(sfv))) logidf
                FROM corpus) foo, corpus ORDER BYdocnum);
SELECT * FROM weights;


Now, rerun cosine distance, look at a few examples, eg. document most similar to X


In general good results, and many stop here.

## Latent Semantic Analysis

Problem: synonymy and polysemy

Two snippets of text may be semantically similar, yet have low cosine simi.
Problem especially serious for short text snippets.
Example:

The president ...
Obama ...

solution: map into latent concepts, lower dimensional subspace


SVD




For more details on computing a singular value decomposition with MADlib, see [this documentation page](http://doc.madlib.net/latest/group__grp__svd.html).

## Clustering

21,578 x 21,578
feasible, but
465,610,084

Larger document collections

rather than find the closest pair across entire collection, find closest pair in random subset (as large as you can handle).
sample as many
