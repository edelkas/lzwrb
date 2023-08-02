**WIP**

# lzwrb

lzwrb is a Ruby gem for LZW encoding and decoding. Main features:

* Pure Ruby, no dependencies.
* Highly configurable (constant/variable code length, bit packing order...). See [Configuration](#configuration).
* Compatible with many LZW specifications, including GIF (see [Presets](#presets)).
* Reasonably fast for pure Ruby (see [Benchmarks](#benchmarks)).

## Table of contents

- [What's LZW?](#what's-lzw)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Configuration](#configuration)
  - [Presets](#presets)
  - [Code length](#code-length)
  - [Packing order](#packing-order)
  - [Clear & Stop codes](#clear--stop-codes)
  - [Custom alphabets](#custom-alphabets)
  - [Verbosity](#verbosity)
- [Benchmarks](#benchmarks)
- [Todo](#todo)
- [Notes](#notes)

## What's LZW?

In short, LZW is a dictionary-based lossless compression algorithm. The encoder scans the data sequentially, building a table of patterns and substituting them in the data by their corresponding code. The decoder, configured with the same settings, will recognize the same patterns and generate the same table, thus being able to recover the original data from the sequence of codes.

The original algorithm used constant code lengths (typically 12 bits), but this is wasteful, specially for data that can be represented with significantly fewer bits, thus variable code length was introduced. Another common feature is the usage of special _Clear_ and _Stop_ codes: When the table is full, the encoder and decoder have to reinitialize it, but this can also be done at will using the Clear code. Likewise, the Stop code indicates the end of the data, which may actually be necessary to avoid ambiguity (see [Clear & Stop codes](#clear--stop-codes)). See [Configuration](#configuration) for a more in-depth description of these and other features, and refer to the [Wikipedia article](https://en.wikipedia.org/wiki/Lempel%E2%80%93Ziv%E2%80%93Welch) for a more thorough explanation.

Nowadays, LZW has largely been replaced by other algorithms that provide a better compression ratio, notably [Deflate](https://en.wikipedia.org/wiki/Deflate), implemented by the ubiquitous [zlib](https://en.wikipedia.org/wiki/Zlib) and formats like Zip or GZip, and used in a plethora of file formats, like PNG images. Deflate also provides a faster decoding speed, though encoding is usually slower. Nevertheless, LZW still has its place in more classic formats yet in use, like GIF and TIFF images, PDF files, or the classic UNIX compress utility.

## Installation
_(This section is not accurate yet, since the tool hasn't been packaged into a gem yet, so it needs to be installed via cloning the repo)_

The setup procedure is completely standard.

### Using Bundler

With [Bundler](https://bundler.io/#getting-started) just add the following line to your Gemfile:

```ruby
gem 'lzw'
```
And then install via `bundle install`.

### Using RubyGems

With Ruby's package manager, just execute the following command on the terminal:
```
gem install lzw
```

You many need admin privileges (e.g. `sudo` in Linux). Beware of using sudo if you're using a version manager, like [RVM](https://rvm.io/) or [rbenv](https://github.com/rbenv/rbenv).

## Basic Usage
_(This section is not accurate yet, since the tool hasn't been packaged into a gem yet, so it needs to be used via cloning the repo first)_

Require the gem, create an `LZW` object with the desired settings and run the `encode` and `decode` methods.

The following example uses the default configuration, see the next section for a list of all the available settings, which can be provided to the constructor via keyword arguments.

```ruby
require 'lzw'
lzw = LZW.new
data = ...
cmp = lzw.encode(data)
res = lzw.decode(cmp)
puts res == data
```

Output sample:
```
Test
```
Note: The output can be reduced or suppressed (or detailed), see [Verbosity](#verbosity).

## Configuration

Most of the usual options for the LZW algorithm can be configured individually by supplying the appropriate keyword arguments in the constructor. Additionally, there are several presets available, i.e., a selection of setting values with a specific purpose (e.g. best compression, fastest encoding, compatible with GIF...). Examples:

```ruby
lzw1 = LZW.new(preset: :gif)
lzw2 = LZW.new(min_bits: 8, max_bits: 16)
lzw3 = LZW.new(preset: :fast, clear: true, stop: true)
```

Individual settings may be used together with a preset, in which case the individual setting takes preference over the value that may be set by the preset, thus enabling the fine-tuning of a specific preset.

The following options are available:

Argument     | Type    | Default   | Description
------------ | ------- | --------- | ---
`:preset`    | Symbol  | None      | Specifies which preset (set of options) to use. See [Presets](#presets).
`:bits`      | Integer | None      | Code length in bits, for constant length mode. See [Code length](#code-length).
`:min_bits`  | Integer | 8         | Minimum code length in bits, for variable length mode. See [Code length](#code-length).
`:max_bits`  | Integer | 16        | Maximum code length in bits, for variable length mode. See [Code length](#code-length).
`:clear`     | Boolean | False     | Whether to use Clear codes or not. See [Clear & Stop codes](#clear--stop-codes).
`:stop`      | Boolean | False     | Whether to use Stop codes or not. See [Clear & Stop codes](#clear--stop-codes).
`:deferred`  | Boolean | False     | Whether to use deferred Clear codes for the decoding process. See [Clear & Stop codes](#clear--stop-codes).
`:lsb`       | Boolean | True      | Whether to use LSB or MSB (least/most significant bit packing order). See [Packing order](#packing-order).
`:alphabet`  | Array   | `BINARY`  | List of characters that compose the data to encode. See [Custom alphabets](#custom-alphabets).
`:safe`      | Boolean | False     | Perform first pass during encoding process for data integrity verification. See [Custom alphabets](#custom-alphabets).
`:verbosity` | Symbol  | `:normal` | Specifies the amount of detail to print to the console. See [Verbosity](#verbosity).

### Presets

Presets specify the value for several configuration options at the same time, with a specific goal in mind (typically, to optimize a certain aspect, or to be compatible with certain format). They can be used together with individual settings, in which case the latter take preference.

The following presets are currently available:

Preset | Description
--- | ---
`:best` | Aimed at best compression, uses variable code length (8-16 bits), no special codes and LSB packing.
`:fast` | Aimed at fastest encoding, uses a constant code length of 16 bits, no special codes and LSB packing.
`:gif` | This is the exact specification implemented by the GIF format, uses variable code length (8-12 bits), clear and stop codes, and LSB packing.

Their descriptive names are based on the average case. However, it is possible on strange samples for the `:best` compression to actually be worse than many other settings.

For example, on highly random samples, most patterns are very short, perhaps only 1 or 2 characters long, and thus substituting them with a long code can end up being counterproductive. In these cases, a smaller code length might be preferable. In fact, on this kind of data LZW encoding may end up increasing the size, and thus not being suitable at all.

### Code length

The different code length parameters specify how many bits are used when packing each of the codes generated by the LZW algorithm into the final output string during the encoding process.

The encoder and the decoder need to agree on these values beforehand, otherwise, the decoder will just see garbled binary data when trying to read an encoded stream. This does not pose a problem when using this gem, since the configuration of the `LZW` object can only be done during initialization, so as long as both encoding and decoding are done with the same object, the configuration will match.

Classically, two different modes are common, *constant length* and *variable length*.

- Constant length mode uses the same bit size for all generated codes, and can be configured by setting the `:bits` parameter to whatever positive integer is desired. It has the disadvantage that there are either too few codes available (if the length is small), leading to poor compression and performance (due to the table needing to be refreshed often); or if the length is big to prevent these issues, then all codes take up substantial storage, again potentially leading to poor compression ratios.
- Variable length mode was introduced to mitigate these issues. It will start with a smaller code size, resulting in more efficiently packed codes, and it will progressively increase the length as required when the table gets full, until eventually reaching a maximum size that will trigger a table refresh, as is the case for the previous mode. To configure this mode, the parameters `:min_bits` and `:max_bits` are provided.

If parameters for both modes are provided, then the constant `:bits` will take priority. Variable length mode typically provides a better compression ratio for most data samples, though the specific optimal values depend on the nature of the data, and experimention might be suited to find them. On the other hand, a constant length of 8, 16, 32 or 64 bits provides the fastest speed, since all codes are then aligned with byte boundaries and code packing can be performed with native byte operations.

The LZW algorithm requires that the code table be initialized with all 1 character strings first, i.e., the [alphabet](#custom-alphabets) must be included in the table. Therefore, the maximum code length must be big enough to hold the alphabet, and it is also irrelevant if the minimum code size is chosen to be smaller than the alphabet's size, as the first codes will nevertheless take up as many bits as required. This will all be corrected by the gem if the user inputs incorrect code lengths.

It is recommended that the maximum code length be at least several bits higher than the size of the alphabet. For example, the default alphabet (binary) requires 8 bits (so that every possible 256 byte values can be encoded), and thus the maximum length should be several bits higher than 8. Otherwise, there will be a significant compression, penalty, as well as a performance penalty, due to the table needing to be refreshed very often due to the lack of slots. It is also pointless in this case to set the minimum code length below 8 bits.

The presets provide good ball-park figures for reasonable code lengths, ranging from 8 to 16 bits for arbitrary binary data. If a smaller alphabet is selected, say, a 5 bit one (32 entries, enough to fit all upper-case latin letters, for instance), then smaller lengths could be reasonable as well.

### Packing order

As explained, the arbitrary code lengths imply that the resulting codes need to be aligned with byte boundaries, and might take multiple bytes. It is therefore important to select how to pack the corresponding bits of the codes into the resulting output string. Two standard schemes are common:

- *Least significant bit* (LSB) packing order will align the least significant bit of the code with the least significant bit available in the last byte of the output, leaving the rest, most significant bits, for the subsequent bytes.
- *Most significant bit* (MSB) packing order will align the most significant bit of the code with the most significant bit available in the last byte of the output, leaving the rest, least significant bits, for subsequent bytes.

Currently, only LSB packing order is implemented, and thus, the `:lsb` configuration parameter is, for now, a placeholder, with the feature being planned.

Both packing orders are commonplace, with LSB being used in formats like GIF and utilities like UNIX compress, and MSB being used in formats like PDF and TIFF, for instance.

### Clear & Stop codes

Another common feature of the LZW algorithm is the addition of special codes, not corresponding to any specific pattern of the data but, instead, to certain control instructions for the decoder.

- The **CLEAR** code specifies to the decoder that the code table should be refreshed immediately. This feature is not technically needed, since the encoder and decoder must agree on all parameters anyways, and therefore are "synchronized", which means they will both refresh the table at the exact same time (whenever it's needed due to the table becoming full).

  However, this feature allows an intelligent encoder (which this one is *not*) to detect when the current table no longer properly reflects the structure of the data, and would benefit from refreshing the table and getting rid of the old codes, thus also reducing the code size (if variable length mode is used) and boosting the performance (codes are found sooner on smaller tables). This encoding feature could be particularly useful for data with significant pattern changes.

  The encoder/decoder can be configured to use clear codes with the `:clear` option. Since the encoder is not intelligent, this option simply means that the encoder will output a clear code before refreshing the table when it's full, thus adding a little overhead. It is therefore only useful for compatibility with formats that require the usage of clear codes, like GIF.
  
- The **STOP** code indicates the end of the data, and that the algorithm should therefore terminate. It is only necessary in two scenarios:

  - If the code length is smaller than 8 bits. In this case, a long string of 0's at the end of the final byte is ambiguous, as it could either be just padding, or actually represent code 0. Therefore, the encoder will force stop codes when the minimum code size is below 8 bits.
  - For compatibility with formats that require stop codes, like GIF.

  The encoder/decoder can be configured to use stop codes with the `:stop` option. As mentioned, stop codes might be used even this option is not set, or set to false, if the encoded deems it necessary (a warning will be issues in those cases).

Another relevant option is **deferred clear codes**. An intelligent encoder can choose not to refresh the code table even when it's full, thus relying on the current one, without adding any new codes, until it deems it useful, at which point it will output a clear code as a signal for the decoder. A decoder would then have to be configured accordingly, such that it doesn't refresh the code table automatically - which is the standard behaviour - unless it receives an explicit clear code.

This feature can be set using the `:deferred` option during initialization. It will only affect the decoder, since the encoder is not intelligent and will therefore never choose to output clear codes prematurely nor in deferred fashion, but rather, precisely when the code table is full. Nevertheless, it is necessary if one wants to decode data that was encoded with this feature on.

Some formats, like GIF, employ this feature. In fact, it caused a great deal of confusion with developers, so much so that the cover of the GIF specification deals with this explanation. To this day, many pieces of software cannot properly decode GIF files that use deferred clear codes, since their decoder automatically refresh the code table when it's full.

### Custom alphabets

As mentioned before, this algorithm can work for arbitrary data composed of characters from any character set, or *alphabet*. By default, this gem will use a binary alphabet of size 256 containing all possible byte values, which, therefore, is suitable to encode and decode any arbitrary piece of data.

It is the recommended alphabet to use if in doubt or if binary data is meant to be encoded. Even if the data to be encoded is just text, if it is Unicode it is probably still best to use the default binary alphabet.

Nevertheless, if data with composed by a substantially smaller set of symbols is meant to be encoded, the full alphabet might be overkill, and a smaller alphabet could be better suited, leading to better compression due to the potential to use smaller code lengths.

This can be configured with the `:alphabet` option of the constructor, which receives an array with all the characters the data is (supposedly) composed of.

For example, if the data to be encoded is composed only of bytes 0 through 7, the array
```ruby
["\x00", "\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07"]
```
could be used, and a minimum code length of only 3 bits could be set. The gem comes equipped with a few default alphabets as constants, for instance, `LZW::HEX_UPPER` contains all 16 possible hex digits in uppercase, and the default alphabet, `LZW::BINARY`, contains all possible 256 byte values. See the `LZW` class for a full list. Nevertheless, an arbitrary array can be used here, as long as it's composed only of 1-character strings.

Note that if the provided alphabet does not contain all the symbols that compose the data to be encoded, this will result in unexpected and incorrect behaviour; most likely an exception, although in some rare cases it could just result in garbled data. Therefore, the user should do either of the following:

- Ensure the data is composed solely by characters from the alphabet. This will never be a problem if the default alphabet (binary) is used, since that can be used to encode arbitrary data. As mentioned, this is the recommended option unless the data can clearly benefit from a smaller alphabet.
- Use the `:safe` option in the constructor, which will always perform a first pass before encoding to ensure that the provided data is indeed composed only of characters from the alphabet. This option, naturally, incurs in a performance penalty for the encoding process (see [Benchmarks](#benchmarks)) that depends on the length of the data. Thus, whenever speed is crucial, the first option is preferable.

### Verbosity

The amount of information logged to the terminal by the encoder and decoder can be set using the `:verbosity` option of the constructor, which takes any of the following symbols:

Value | Description
--- | ---
`:silent` | Don't log anything.
`:minimal` | Log only errors.
`:quiet` | Log errors and warnings.
`:normal` | Also log brief encoding/decoding info (time, compression ratio, speed...).
`:debug` | Also log additional debug information of the encoding / decoding process, such as when the code table gets refreshed, or the traces of the exceptions, if any.

The default value is `:normal`.

## Benchmarks

On mid-range computers (2nd gen Ryzen 5, 7th gen i5) I've obtained 5 mbit/s encoding speeds and 9 mbit/s decoding speeds.

The optional `:safe` setting, which performs a first pass in the encoding process to ensure data integrity (see [Custom alphabets](#custom-alphabets)), seems to incur roughly in a 15% speed penalty, i.e., encoding bitrate is decreased by about 15%. This setting does not affect the decoding process.

## Todo

Eventually I'd like to have the following extra features tested and implemented:

### Main features

* Most significant bit (MSB) packing order.
* "Early change" support.
* Support for TIFF and PDF (requires the 2 features above).
* Support for UNIX compress (has a bug).

### Smaller additions

* Option to disable automatic table reinitialization.
* Choice between plain and rich logs.

### Optimizations

* Native packing for codes of constant width of 8, 16, 32 or 64 bits for extra speed.
* Use a Trie instead of a Hash for the encoding process.

### Development

* Add docs.
* Add changelog.
* Add Rake tests.
* Package as gem.

## Notes

* **Concurrency**: The `LZW` objects are _not_ thread safe. If you want to encode/decode in parallel, you must create a separate object for each thread, even if they use the same exact configuration.
* **Custom alphabets**: If you change the default alphabet (binary), ensure the data to be encoded can be expressed solely with that alphabet, or alternatively, specify the `safe` option to the encoder.