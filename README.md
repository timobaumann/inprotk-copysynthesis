#Incremental Copy Synthesis
A project to try out copy synthesis that can be influenced incrementally (i.e., change speed, prosody, etc.) 

##workflow and classes in InproTK: 
 * have an IU structure that (at least) has a list of SysSegmentIUs (as different phonemes are lengthened differently, I believe) and/or WordIUs (as these are required to be able to change/drop parts of the message
 * typically, IU structures have been created from TTS and already contain a HTSModel (that contains all relevant data for synthesis)
 * SysSegmentIUs can also (in principle, unclear if this works) create HTSModels themselves by probing for relevant features and finding the proper PDFs 
 * SysSegmentIUs locally perform HMM parameter optimization which yields a list of FullPFeatureFrames (locally called hmmSynthesisFeatures)
	→ I can (simply) append the FullPFeatureFrames (hmmSynthesisFeatures) from the csv to these SysSegmentIUs
	→ SysSegmentIUs have a constructor that allows to set FullPFeatureFrames
	→ what calls this constructor?
 * FullPFeatureFrames are sequentialized in a FullPStream. There are multiple implementations of this, one is IUBasedFullPStream, another is about HTS compatibility
 * VocodingAudioStream vocodes based on the FullPStream and yields an audio stream.
 
first test of a possible copy synthesis:
 * have a FullPStream that reads line-by-line the information needed into FullPFeatureFrames line-by-line in a FullPFeatureFrames.
 * should be fairly easy.
 * shows whether the parameters work as intended → they do.
 * only difficulty: there's a HMMData object that holds configuration data that I'll need to replace by a fixed implementation → not needed, I simply use one hard-coded.

### Next steps.

##Workbench for creating feature files
The workbench is used to prepare files that can be synthesised incrementally. It uses the Mary Voicebuilding setup (in particular: SPTK with Mary-specific changes). It also uses the BAS WebMAUS-API for text-to-speech alignment.

The Makefile there can be used to turn all wavefiles in `input/` into feature files that can be used by the vocoder (plus TextGrid files that are based on the files in `txt/` that can be used to build the correct IU structures in order to yield control over synthesis) in `cmp/` and `tg/`, respectively.

###DEPENDENCIES for running the workbench: 
 * praat in /usr/bin/praat
 * TGtool.pl in your path. Please install the most recent Intelida toolkit version from git@bitbucket.org:inpro/intelida.git .


# TODOS: 
 * test that aborting a sentence actually works
 * turn this repo into an application that starts ProsodyDemonstrator with Kerstin as pre-set utterance
