package inpro.synthesis;

import inpro.incremental.unit.SysSegmentIU;
import inpro.incremental.unit.WordIU;
import inpro.synthesis.hts.FileBackedFullPStream;
import inpro.synthesis.hts.VocodingAudioStream;

import java.io.InputStream;
import java.net.URL;
import java.util.Collections;
import java.util.List;

public class MaryAdapterCopySynthesis extends MaryAdapter5internal {

    public MaryAdapterCopySynthesis() {
        super();
        VocodingAudioStream.gain = 0.3;
    }

    @Override
    /** turn text (including prosodic markup) into lists of WordIUs */
    protected List<? extends WordIU> text2IUs(String tts, boolean keepPhrases, boolean connectPhrases) {
        //InputStream is = text2maryxml(tts); // TODO: use something different here
        InputStream is;
        try {
            is = new URL(tts+".maryxml").openStream();
            List<? extends WordIU> ius = createIUsFromInputStream(is, Collections.emptyList(), keepPhrases, connectPhrases);
            SysSegmentIU seg = (SysSegmentIU) ius.get(0).getFirstSegment();
            FileBackedFullPStream feats = new FileBackedFullPStream(new URL(tts+".cmp"));
            while (seg != null) {
                seg.hmmSynthesisFeatures = feats.getSpan((int) (seg.startTime() * 200), (int) (seg.endTime() * 200));
                seg = (SysSegmentIU) seg.getNextSameLevelLink();
            }
            return ius;
        } catch (Exception e) {
            System.err.println("trouble finding files for CopySynthesis of " + tts);
        }
        return super.text2IUs(tts, keepPhrases, connectPhrases);
    }

}
