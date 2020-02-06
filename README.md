#Incremental Copy Synthesis
A project to try out copy synthesis that can be influenced incrementally (i.e., change speed, prosody, etc.) 

workflow and classes in InproTK: 
 * have an IU structure that (at least) has a list of SysSegmentIUs
 * typically, IU structures have been created from TTS and already contain a HTSModel (that contains all relevant data for synthesis)  
 * SysSegmentIUs can also (in principle, unclear if this works) create HTSModels themselves by probing for relevant features and finding the proper PDFs 
 * SysSegmentIUs locally perform HMM parameter optimization which yields a list of FullPFeatureFrames (locally called hmmSynthesisFeatures)
 * FullPFeatureFrames are sequentialized in a FullPStream. There are multiple implementations of this, one is IUBasedFullPStream, another is about HTS compatibility
 * VocodingAudioStream vocodes based on the FullPStream and yields an audio stream.
 
first test of a possible copy synthesis:
 * have a FullPStream that reads line-by-line the information needed into FullPFeatureFrames line-by-line in a FullPFeatureFrames.
 * should be fairly easy.
 * shows whether the parameters work as intended
 * only difficulty: there's a HMMData object that holds configuration data that I'll need to replace by a fixed implementation.
  
##Workbench
The workbench is used to prepare files that can be synthesised incrementally. It uses the Mary Voicebuilding setup (in particular: SPTK with Mary-specific changes). It also uses the BAS WebMAUS-API for text-to-speech alignment. 
