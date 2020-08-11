package inpro.synthesis;

import inpro.audio.AudioUtils;
import inpro.audio.DispatchStream;
import inpro.incremental.unit.IU;
import inpro.incremental.unit.WordIU;
import inpro.synthesis.hts.IUBasedFullPStream;
import inpro.synthesis.hts.VocodingAudioStream;
import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;

/* plan: build a marytts adapter that gets
   - some (annotated) marytts to turn this into an IU structure
        → consider what to do with file-initial pauses. maybe I simply remove the corresponding features and the pause from the TextGrid?
   - some form of FileBackedFullPStream or whatever it needs to
     so that features can be stored in the SysSegmentIUs directly

        → at present, SysSegmentIU's hmmSynthesisFeatures
        can only be set in the constructor, there are no further setters.
        → setting the hmmSynthesisFeatures post-hoc sounds like the by-far best way of doing it
        (given that everything else would require way too much packing/unpacking along the way.

   - how do I place an alternative to MaryAdapter5internal? Or should I *add* the CopySynthesis functionality to 5internal? (not really, I believe)


methods implemented in MaryAdapter
    stuff responsible for overall setup:
        initializeMary(), getInstance()
    helper stuff:
        wrapWithToplevelTag()
    what was once thought as the main method to be overridden
        process() → turns a query of some type into output of some type ; the versatility of this is actually not really used by InproTK anymore, is it?

        methods that call process():
            getAudioInputStreamFromMary(), getInputStreamFromMary()
            → these in turn are called by:
                text2maryxml(), fullySpecifiedMarkup2maryxml(), legacy stuff

    methods that turn text into fully specified markup including "REALISED_ACOUSTPARAMS"
        text2maryxml() → for text, →→ I'll need this only for text, I believe
        fullySpecifiedMarkup2maryxml() → for "ACOUSTPARAMS"

    methods that turn text into IU structures:
        text2PhraseIUs(), text2WordIUs (why both?)
        text2IUs() → does the heavy lifting for text2SometypeIUs above
        fullySpecifiedMarkup2PhraseIUs() → special version of text2PhraseIUs, I believe

        createIUsFromInputStream() → uses TTSUtil to create IU structure

    legacy stuff for MBROLA, lol

methods in MaryAdapter5internal
    constructor → sets up the "maryInterface" which is a Mary class and main entrypoint to MaryTTs

    process() does the heavy lifting but nothing (little?) about IHTSE / InteractiveHTSEngine
            → IHTSE is embedded into the mary.configuration and very indirectly called from there, though

    text2IUs() → uses access to IHTSE to embed synthesis data from IHTSE
    fullySpecifiedMarkup2PhraseIUs() → likewise
        → this is never used

   downstream from that, everything else should be easy
 */

public class MaryAdapterCopySynthesisTest {

    @Test
    public void testText2WordIUs() {
        System.setProperty("mary.version", "inpro.synthesis.MaryAdapterCopySynthesis");
        MaryAdapter ma = MaryAdapter.getInstance();
        List<WordIU> ius = ma.text2WordIUs("file:src/test/resources/inpro/synthesis/hts/DE_1234");
        assertEquals(8, ius.size());
    }

    @Test
    public void testSpeechOutput() throws InterruptedException {
        System.setProperty("mary.version", "inpro.synthesis.MaryAdapterCopySynthesis");
        DispatchStream d = DispatchStream.drainingDispatchStream();

        List<? extends IU> wordIUs = MaryAdapter.getInstance().text2WordIUs("file:src/test/resources/inpro/synthesis/hts/DE_1234");
        d.playStream(AudioUtils.get16kAudioStreamForVocodingStream(new VocodingAudioStream(new IUBasedFullPStream(wordIUs.get(0)), MaryAdapter5internal.getDefaultHMMData(), true)), true);
        // wait for synthesis:
        d.waitUntilDone();
        Thread.sleep(1000);
        d.shutdown();
    }

}
