# Ceph Erasure Coding Interface

##### ErasureCodeInterface

Ceph requires all erasure code to implement this erasure code interface such that the code can be used in ceph.

It has the following fuctions:

```c++
class ErasureCodeInterface {
  public:
    virtual ~ErasureCodeInterface() {}
    virtual int init(ErasureCodeProfile &profile, std::ostream *ss) = 0;
    virtual const ErasureCodeProfile &get_profile() const = 0;
    virtual int create_rule(const std::string &name,
			    CrushWrapper &crush,
			    std::ostream *ss) const = 0;
    virtual unsigned int get_chunk_count() const = 0;
    virtual unsigned int get_data_chunk_count() const = 0;
    virtual unsigned int get_coding_chunk_count() const = 0;
    virtual int get_sub_chunk_count() = 0;
    virtual unsigned int get_chunk_size(unsigned int object_size) const = 0;
    virtual int minimum_to_decode(const std::set<int> &want_to_read,
                                  const std::set<int> &available,
                                  std::map<int, std::vector<std::pair<int, int>>> 
                                  *minimum) = 0;
    virtual int minimum_to_decode_with_cost(const std::set<int> &want_to_read,
                                            const std::map<int, int> &available,
                                            std::set<int> *minimum) = 0;
    virtual int encode(const std::set<int> &want_to_encode,
                       const bufferlist &in,
                       std::map<int, bufferlist> *encoded) = 0;
    virtual int encode_chunks(const std::set<int> &want_to_encode,
                              std::map<int, bufferlist> *encoded) = 0;
    virtual int decode(const std::set<int> &want_to_read,
                       const std::map<int, bufferlist> &chunks,
                       std::map<int, bufferlist> *decoded, int chunk_size) = 0;
    virtual int decode_chunks(const std::set<int> &want_to_read,
                              const std::map<int, bufferlist> &chunks,
                              std::map<int, bufferlist> *decoded) = 0;
    virtual const std::vector<int> &get_chunk_mapping() const = 0;
    virtual int decode_concat(const std::map<int, bufferlist> &chunks,
			      bufferlist *decoded) = 0;
};
```



Basically, **encode** and **decode** are called for erasure coding contruction and repair. If the object is small enough, then the erasure coding process only needs one call of **encode** or **decode** to finish erasure coding process. 

##### encode

Now we suppose that **k=3, m=2**, the encode process looks like this

```c++
set<int> want_to_encode(0, 1, 2, // data chunks
                        3, 4     // coding chunks
                       );
bufferlist in = "ABCDEF";
map<int, bufferlist> encoded
encode(want_to_encode, in, &encoded);
encoded[0] == "AB" // data chunk 0
encoded[1] == "CD" // data chunk 1
encoded[2] == "EF" // data chunk 2
encoded[3]         // coding chunk 0
encoded[4]         // coding chunk 1
```

How to understand the usage of encode interface?

* It requires an integer list, the first k integer refers to the stripe index of the original data chunk while the remaining m integer refers to the stripe index of the parity chunk.
* A bufferlist which contains all input data. How to understand **bufferlist**? We can look the bufferlist as an char\* array, which contains the raw input data. It is the responsibility of **encode** to divide it into small data chunks.
* A map which map the stripe index to data bufferlist. The purpose of this map is for ceph to take out corresponding data chunks out.

##### minimum_to_decode_with_cost

This interface is provided by erasure coding. Given the cost of each chunk to be chosen, the function needs to provide a solution, how the required chunk should be repair.

```c++
set<int> want_to_read(2); // want the chunk containing "EF"
map<int,int> available(
      0 => 1,  // data chunk 0 : available and costs 1
      1 => 1,  // data chunk 1 : available and costs 1
               // data chunk 2 : missing
      3 => 9,  // coding chunk 1 : available and costs 9
      4 => 1,  // coding chunk 2 : available and costs 1
);
set<int> minimum;
minimum_to_decode_with_cost(want_to_read,
                            available,
                            &minimum);
minimum == set<int>(0, 1, 4); // NOT set<int>(0, 1, 3);
```

In this example, we want to read the chunk with the stripe index 2. This can be the case when the chunk[2] is missing and primary OSD wants to repair this missing chunk.

As the input, ceph framework needs to provide the cost for each chunk if it is choosed, in the data structure **available**.

Then the function is expected to return a set called **minimum**, which contains the index that are needed to repair the lost chunk.

##### decode

How decode is performed? This code segment is append to the previous code segment.

```c++
map<int,bufferlist> chunks;
for i in minimum.keys():
  chunks[i] = fetch_chunk(i); // get chunk from storage
map<int, bufferlist> decoded;
decode(want_to_read, chunks, &decoded);
decoded[2] == "EF"
```

The map **chunks** contains the data that are needed to repair the lost chunk.

The map **decoded** contains the data that repaired by the function decode.

##### TestErasureCodeJerasure

Then let's take this test program as an example to learn the usage of the erasure coding interfaces.

We focus on the **encode_decode** test:

The first thing is to initialize the profile

```c++
ErasureCodeProfile profile;
profile["k"] = "2";
profile["m"] = "2";
profile["packetsize"] = "8";
profile["jerasure-per-chunk-alignment"] =
  per_chunk_alignments[per_chunk_alignment];
jerasure.init(profile, &cerr);
```

We can look the profile of "k", "m", "packetsize" and "jerasure-per-chunk-alighment" as the parameters that are needed to initialize the jerasure code. We expect code designer to deal with these parameters themselves.

Then the **init** function is called to initialize the jerasure code.

Then before the encode, ceph prepare the data

```c++
bufferptr in_ptr(buffer::create_page_aligned(LARGE_ENOUGH));
in_ptr.zero();
in_ptr.set_length(0);
const char *payload =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
in_ptr.append(payload, strlen(payload));
bufferlist in;
in.push_back(in_ptr);
int want_to_encode[] = { 0, 1, 2, 3 };
map<int, bufferlist> encoded;
EXPECT_EQ(0, jerasure.encode(set<int>(want_to_encode, want_to_encode+4),
          in,
          &encoded));
EXPECT_EQ(4u, encoded.size());
unsigned length =  encoded[0].length();
EXPECT_EQ(0, memcmp(encoded[0].c_str(), in.c_str(), length));
EXPECT_EQ(0, memcmp(encoded[1].c_str(), in.c_str() + length,
          in.length() - length));
```

The orifinal data are in the bufferlist **in**. **want_to_encode** specifies the stripe index. Then **jerasure.encode** is called for encoding. Actually, we find that there is no **encode** function implemented in ErasureCodeJerasure.cc. This is the function in **ErasureCode.cc**:

```c++
int ErasureCode::encode(const set<int> &want_to_encode,
                        const bufferlist &in,
                        map<int, bufferlist> *encoded)
{
  unsigned int k = get_data_chunk_count();
  unsigned int m = get_chunk_count() - k;
  bufferlist out;
  int err = encode_prepare(in, *encoded);
  if (err)
    return err;
  encode_chunks(want_to_encode, encoded);
  for (unsigned int i = 0; i < k + m; i++) {
    if (want_to_encode.count(i) == 0)
      encoded->erase(i);
  }
  return 0;
}
```

From this code segment, we know that **encode_prepare** is first called and follows **encode_chunks**.

The purpose of **encode_prepare** is to prepare the original data from the bufferlist **in** to be put into the map **encoded**. After data prepared, **encode_chunks** is called.

```c++
int ErasureCode::encode_prepare(const bufferlist &raw,
                                map<int, bufferlist> &encoded) const
{
  unsigned int k = get_data_chunk_count(); // k=2
  unsigned int m = get_chunk_count() - k;  // m=2
  unsigned blocksize = get_chunk_size(raw.length()); // len(payload) is divided into k chunks, so the blocksize here is len(payload)/2
  unsigned padded_chunks = k - raw.length() / blocksize; // zero padding
  bufferlist prepared = raw;

  // in the follow for code segment, original data in raw are put into the map encoded.
  for (unsigned int i = 0; i < k - padded_chunks; i++) {
    bufferlist &chunk = encoded[chunk_index(i)];
    chunk.substr_of(prepared, i * blocksize, blocksize);
    chunk.rebuild_aligned_size_and_memory(blocksize, SIMD_ALIGN);
    assert(chunk.is_contiguous());
  } 
  // if there needs zero padding, then new buffers with zero are put into encoded.
  if (padded_chunks) {
    unsigned remainder = raw.length() - (k - padded_chunks) * blocksize;
    bufferptr buf(buffer::create_aligned(blocksize, SIMD_ALIGN));

    raw.copy((k - padded_chunks) * blocksize, remainder, buf.c_str());
    buf.zero(remainder, blocksize - remainder);
    encoded[chunk_index(k-padded_chunks)].push_back(std::move(buf));

    for (unsigned int i = k - padded_chunks + 1; i < k; i++) {
      bufferptr buf(buffer::create_aligned(blocksize, SIMD_ALIGN));
      buf.zero();
      encoded[chunk_index(i)].push_back(std::move(buf));
    }
  }
  for (unsigned int i = k; i < k + m; i++) {
    bufferlist &chunk = encoded[chunk_index(i)];
    chunk.push_back(buffer::create_aligned(blocksize, SIMD_ALIGN));
  }

  return 0;
}
```

How about **encode_chunks**? It takes the buffer out from **encoded** and set them into a two-dimension char array. Then call **jerasure_encode**.

```c++
int ErasureCodeJerasure::encode_chunks(const set<int> &want_to_encode,
				       map<int, bufferlist> *encoded)
{
  char *chunks[k + m];
  for (int i = 0; i < k + m; i++)
    chunks[i] = (*encoded)[i].c_str();
  jerasure_encode(&chunks[0], &chunks[k], (*encoded)[0].length());
  return 0;
}

void ErasureCodeJerasureReedSolomonVandermonde::jerasure_encode(char **data,
                                                                char **coding,
                                                                int blocksize)
{
  jerasure_matrix_encode(k, m, w, matrix, data, coding, blocksize);
}
```

Now we go back to **TestErasureCodeJerasure**. After the encode it tries to test the decode function. It test the decode in two cases. The first case is that all the data chunks are available, which is the scenario when the client request data when all the data chunks are available in a stripe. The second case is that when there is failures in data chunks, which is the scenario for client degraded read.

```c++
// all chunks are available
    {
      int want_to_decode[] = { 0, 1 }; // we want to read 0 and 1.
      map<int, bufferlist> decoded;
      EXPECT_EQ(0, jerasure._decode(
                    set<int>(want_to_decode, want_to_decode+2), // request
				    encoded, // available
				    &decoded)); // result
      EXPECT_EQ(2u, decoded.size()); 
      EXPECT_EQ(length, decoded[0].length());
      EXPECT_EQ(0, memcmp(decoded[0].c_str(), in.c_str(), length));
      EXPECT_EQ(0, memcmp(decoded[1].c_str(), in.c_str() + length,
			  in.length() - length));
    }
// two chunks are missing 
    {
      map<int, bufferlist> degraded = encoded;
      degraded.erase(0); // delete the data of index 0 and 1
      degraded.erase(1);
      EXPECT_EQ(2u, degraded.size());
      int want_to_decode[] = { 0, 1 };
      map<int, bufferlist> decoded;
      EXPECT_EQ(0, jerasure._decode(set<int>(want_to_decode, want_to_decode+2),
				    degraded,
				    &decoded));
      // always decode all, regardless of want_to_decode
      EXPECT_EQ(4u, decoded.size()); 
      EXPECT_EQ(length, decoded[0].length());
      EXPECT_EQ(0, memcmp(decoded[0].c_str(), in.c_str(), length));
      EXPECT_EQ(0, memcmp(decoded[1].c_str(), in.c_str() + length,
			  in.length() - length));
    }
```

Now let's look at **_decode** function in **ErasureCode.cc**

```c++
int ErasureCode::_decode(const set<int> &want_to_read,
			 const map<int, bufferlist> &chunks,
			 map<int, bufferlist> *decoded)
{
  vector<int> have; // take the index from chunks out and put into have.
  have.reserve(chunks.size());
  for (map<int, bufferlist>::const_iterator i = chunks.begin();
       i != chunks.end();
       ++i) {
    have.push_back(i->first);
  } // now, have contains all available index.
  if (includes(
	have.begin(), have.end(), want_to_read.begin(), want_to_read.end())) {
    // if the requrest index in in available index have, we just read data from chunks and set it in decoded.
    for (set<int>::iterator i = want_to_read.begin();
	 i != want_to_read.end();
	 ++i) {
      (*decoded)[*i] = chunks.find(*i)->second;
    }
    return 0;
  }
  unsigned int k = get_data_chunk_count();
  unsigned int m = get_chunk_count() - k;
  unsigned blocksize = (*chunks.begin()).second.length();
  for (unsigned int i =  0; i < k + m; i++) {
    if (chunks.find(i) == chunks.end()) {
      // if current index has no data in chunks, create new buffer
      bufferlist tmp;
      bufferptr ptr(buffer::create_aligned(blocksize, SIMD_ALIGN));
      tmp.push_back(ptr);
      tmp.claim_append((*decoded)[i]);
      (*decoded)[i].swap(tmp);
    } else {
      (*decoded)[i] = chunks.find(i)->second;
      (*decoded)[i].rebuild_aligned(SIMD_ALIGN);
    }
  }
  return decode_chunks(want_to_read, chunks, decoded);
}
```

Now let's look at **decode_chunks**

```c++
int ErasureCodeJerasure::decode_chunks(const set<int> &want_to_read,
				       const map<int, bufferlist> &chunks,
				       map<int, bufferlist> *decoded)
{
  unsigned blocksize = (*chunks.begin()).second.length();
  int erasures[k + m + 1];  // contains erasured index
  int erasures_count = 0;
  char *data[k];  // put data in this array
  char *coding[m];  // put code in this array
  for (int i =  0; i < k + m; i++) {
    if (chunks.find(i) == chunks.end()) {
      erasures[erasures_count] = i;
      erasures_count++;
    }
    if (i < k)
      data[i] = (*decoded)[i].c_str();
    else
      coding[i - k] = (*decoded)[i].c_str();
  }
  erasures[erasures_count] = -1;

  assert(erasures_count > 0);
  return jerasure_decode(erasures, data, coding, blocksize);
}

int ErasureCodeJerasureReedSolomonVandermonde::jerasure_decode(int *erasures,
                                                                char **data,
                                                                char **coding,
                                                                int blocksize)
{
  return jerasure_matrix_decode(k, m, w, matrix, 1,
				erasures, data, coding, blocksize);
}
```

#### Summary

* init() is used to initialize an erasure code, set up related parameters
* For encode, ```ErasureCode::encode``` is called. Inside this function, ```ErasureCode::encode_prepare``` and ```ErasureCode::encode_chunks``` are called
  * Inside ```ErasureCode::encode_prepare```, code needs to provide ```get_chunk_size()```, which is used to divide input data into several splits.
  * Inside ```ErasureCode::encode_chunks```, code do the encoding
* For decode, users need to provide ```decode_chunks``` to repair lost data.

