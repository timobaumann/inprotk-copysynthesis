# loosely based on HTS feature extraction Makefile as adapted for MaryTTS
INPUTFILES=$(wildcard input/*.wav)
OUTPUTFILES=$(patsubst input/%.wav,cmp/%.cmp,$(INPUTFILES)) $(patsubst input/%.wav,tg/%.TextGrid,$(INPUTFILES))

LOWERF0=60 # lower limit for f0 extraction (Hz)
UPPERF0=180 # upper limit for f0 extraction (Hz)

SAMPFREQ    = 16000   # Sampling frequency (48kHz)
FRAMELEN    = 400   # Frame length in point (1200 = 48000 * 0.025)
FRAMESHIFT  = 80 # Frame shift in point (240 = 48000 * 0.005)
WINDOWTYPE  = 1 # Window type -> 0: Blackman 1: Hamming 2: Hanning
NORMALIZE   = 1  # Normalization -> 0: none  1: by power  2: by magnitude
FFTLEN      = 512     # FFT length in point
FREQWARP    = 0.42   # frequency warping factor
MGCORDER    = 34   # order of MGC analysis

STRORDER    = 5     # order of STR analysis, number of filter banks for mixed excitation
STRFILTERNAME = filters/mix_excitation_5filters_99taps_16Kz.txt

TCLSH = /usr/bin/tclsh
BC    = /usr/bin/bc
X2X     = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/x2x
FRAME   = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/frame
WINDOW  = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/window
MGCEP   = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/mcep
MINMAX  = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/minmax
STEP    = /home/timo/uni/experimente/070_voiceBuilding/sptk-target/bin/step



# filter taps filename for voicing stregths analysis in mixed excitation
STRFILTERNAME = filters/mix_excitation_5filters_99taps_16Kz.txt

wav/%.wav : input/%.wav
	sox $< --bits 16 --encoding signed-integer --endian little --rate 16k --channels 1 $@

raw/%.raw : wav/%.wav
	sox $< --bits 16 --encoding signed-integer --endian little $@

lf0/%.lf0 : wav/%.wav
	scripts/praat ../$< $(LOWERF0) $(UPPERF0) > $@

mgc/%.mgc : raw/%.raw
	@echo "Extracting MGC coefficients from $*"
	min=`$(X2X) +sf $< | $(MINMAX) | $(X2X) +fa | head -n 1`; \
	max=`$(X2X) +sf $< | $(MINMAX) | $(X2X) +fa | tail -n 1`; \
	if [ -s $< -a $${min} -gt -32768 -a $${max} -lt 32767 ]; then \
		$(X2X) +sf $< | \
		$(FRAME) -l $(FRAMELEN) -p $(FRAMESHIFT) | \
		$(WINDOW) -l $(FRAMELEN) -L $(FFTLEN) -w $(WINDOWTYPE) -n $(NORMALIZE) | \
		$(MGCEP) -a $(FREQWARP) -m $(MGCORDER) -l $(FFTLEN) -e 1.0E-08 | \
		$(X2X) +f +a35 > $@; \
	fi

str/%.str : raw/%.raw
	echo "Extracting strengths from $*"; \
	count=`echo "0.005 * $(SAMPFREQ)" | $(BC) -l`; \
	$(STEP) -l `printf "%.0f" $${count}` | \
	$(X2X) +fs > $*.tmp.head; \
	count=`echo "0.025 * $(SAMPFREQ)" | $(BC) -l`; \
	$(STEP) -l `printf "%.0f" $${count}` | \
	$(X2X) +fs > $*.tmp.tail; \
	cat $*.tmp.head $< $*.tmp.tail > $*.tmp; \
	$(TCLSH) scripts/get_str.tcl -l -H $(UPPERF0) -L $(LOWERF0) -p $(FRAMESHIFT) -r $(SAMPFREQ) -f $(STRFILTERNAME) -n $(STRORDER) $*.tmp | \
	$(X2X) +a +a +a5 > $@ ; \
	rm $*.tmp.head $*.tmp.tail $*.tmp

cmp/%.cmp : mgc/%.mgc str/%.str lf0/%.lf0
	paste mgc/$*.mgc str/$*.str lf0/$*.lf0 | awk 'NF==41' > $@

tg/%.TextGrid : wav/%.wav input/%.txt
	curl -s `curl -s -X POST -H 'content-type: multipart/form-data' -F SIGNAL=@wav/$*.wav -F LANGUAGE=deu-DE -F TEXT=@input/$*.txt 'https://clarin.phonetik.uni-muenchen.de/BASWebServices/services/runMAUSBasic'|grep '<downloadLink>' |sed 's"^.*<downloadLink>"";s"</downloadLink>.*""'` > $@

clean : 
	rm -f cmp/*.cmp lf0/*.lf0 mgc/*.mgc raw/*.raw wav/*.wav str/*.str tg/*.TextGrid

all : $(OUTPUTFILES)


