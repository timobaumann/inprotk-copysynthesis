# Incremental Copy Synthesis
A project that adds copy synthesis instead of actual text-to-speech synthesis to InproTK.
In contrast to _plain_ audio files, copy synthesis can be influenced incrementally (i.e., change speed, prosody, etc.) just like all other incremental speech output from InproTK

## Workflow and classes in InproTK: 
*Firstly*, synthesis can be effected from feature files that contain all parameters that need to be passed to the vocoder (one line per 5ms). See "Workbench" below on how these are created. There's demo code for this in test/java/; this is just the underlying technology for the main use-case.

*Secondly*, for full-fledged incremental synthesis, the speech structure (phonemes, words, phrases) need to be available in addition to vocoding features (see above). These can be created from TextGrid files, which, in turn, can be created by an automatic alignment service (WebMAUS) -- you'll need internet access for the web service! 
*Therefore, a maryxml-file is required, as well as the corresponding feature file (.cmp) in the same name and path.*

Full incremental copy-synthesis is performed via the MaryAdapter specified in `src/main/java/inpro/synthesis/MaryAdapterCopySynthesis.java`. This can be used as the relevant speech synthesis Adapter for inprotk via the system property `mary.version` which needs to be set as follows (on the commandline prepend -D to set the system property): `-Dmary.version=inpro.synthesis.MaryAdapterCopySynthesis`. This is, e.g. handled in `build.gradle` application section.

### Demo application and usage
This repository holds a demo application and corresponding feature&maryxml files. Type `./gradlew run` to execute it. 

You get the standard InproTK-ProsodyDemonstrator which shows as "input text" a file URL to the file to be copy-synthesized. In this case, it's `file:kerstin--07`. Click the play button and the text will change to what's specified in the corresponding  `kerstin--07.maryxml` and the features from `kerstin--07.cmp` will be synthesized alongside.

Note that you are able to manipulate properties of synthesis via the GUI. In particular, see if you like the results of the "distance stressing" slider. It's safer to re-start the application inbetween synthesis attempts. 

You will notice that "normal" TTS will be executed if copysynthesis files cannot be loaded because their path is wrong (or any other reason).

## Workbench for creating feature files
The workbench is used to prepare files that can be synthesised incrementally. It uses the Mary Voicebuilding setup (in particular: SPTK with Mary-specific changes). It also uses the BAS WebMAUS-API for text-to-speech alignment.

The Makefile there can be used to turn all wavefiles in `input/` into feature files that can be used by the vocoder (plus MaryXML files that are based on correspondingly named `txt` files also in `input/` that can be used to build the correct IU structures in order to yield control over synthesis) in `cmp/` and `maryxml/`, respectively.

## Usage:
* ensure that you start a system that uses InproTK with the `mary.version` property set as described above (if this yields errors that indicate that some service cannot be found, mail Timo)
* instead of entering what you want to be synthesized as text, enter the file-URL prefix that, when extended with `.maryxml`/`.cmp` yields the corresponding files. 

## DEPENDENCIES for running the workbench: 
 * sox 
 * praat in /usr/bin/praat
 * to install these dependencies on Ubuntu: `apt-get install sox praat`
 * `TGtool.pl` is included in workbench/scripts/. Please see Intelida toolkit at git@bitbucket.org:inpro/intelida.git for details.
 * call `cpan install Statistics::Lite XML::Quote Term::Shell` to install the external dependencies for TGtool

# TODOS: 
 * test that aborting a sentence actually works (-:
