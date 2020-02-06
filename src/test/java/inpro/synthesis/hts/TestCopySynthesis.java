package inpro.synthesis.hts;

import inpro.audio.AudioUtils;
import inpro.audio.DispatchStream;
import marytts.htsengine.HMMData;
import marytts.htsengine.HMMVoice;
import marytts.modules.synthesis.Voice;
import marytts.util.MaryRuntimeUtils;
import org.testng.annotations.Test;

public class TestCopySynthesis {

    @Test
    public void testCopySynthesis() throws Exception {
        DispatchStream ds = DispatchStream.drainingDispatchStream();
        MaryRuntimeUtils.ensureMaryStarted();
        Voice v = Voice.getVoice("bits1-hsmm");
        HMMData hmmData = ((HMMVoice) v).getHMMData();
//        hmmData.setNumFilters(5);
//        hmmData.setOrderFilters(99);
//        hmmData.setUseMixExc(true);
        VocodingAudioStream vas = new VocodingAudioStream(new FileBackedFullPStream(TestCopySynthesis.class.getResource("DE_1234.cmp")), hmmData, true);
        ds.playStream(AudioUtils.get16kAudioStreamForVocodingStream(vas));
        Thread.sleep(1000);
        ds.waitUntilDone();
        ds.shutdown();
    }

}
