package inpro.synthesis.hts;

import inpro.audio.AudioUtils;
import inpro.audio.DispatchStream;
import marytts.htsengine.HMMData;
import marytts.htsengine.HMMVoice;
import marytts.modules.synthesis.Voice;
import marytts.util.MaryRuntimeUtils;
import org.junit.Test;

public class TestDirectCopySynthesis {

    @Test
    public void testDirectCopySynthesis() throws Exception {
        DispatchStream ds = DispatchStream.drainingDispatchStream();
        MaryRuntimeUtils.ensureMaryStarted();
        Voice v = Voice.getVoice("bits1-hsmm");
        HMMData hmmData = ((HMMVoice) v).getHMMData();
//        hmmData.setNumFilters(5);
//        hmmData.setOrderFilters(99);
//        hmmData.setUseMixExc(true);
        VocodingAudioStream.gain = 0.3;
        VocodingAudioStream vas = new VocodingAudioStream(new FileBackedFullPStream(TestDirectCopySynthesis.class.getResource("kerstin--07.cmp")), hmmData, true);
        ds.playStream(AudioUtils.get16kAudioStreamForVocodingStream(vas));
        Thread.sleep(1000);
        ds.waitUntilDone();
        ds.shutdown();
    }

}
