package inpro.synthesis.hts;

import jdk.nashorn.api.scripting.URLReader;

import java.io.*;
import java.net.URL;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class FileBackedFullPStream extends FullPStream {

    BufferedReader csvReader;
    List<FullPFeatureFrame> frames;
    int index;

    public FileBackedFullPStream(String filename) throws IOException {
        this(new File(filename));
    }

    public FileBackedFullPStream(File file) throws IOException {
        this(new FileReader(file));
    }

    public FileBackedFullPStream(URL url) throws IOException {
        this(new URLReader(url));
    }

    public FileBackedFullPStream(Reader reader) throws IOException {
        csvReader = new BufferedReader(reader);
        frames = new ArrayList<>();
        String line;
        while ((line = csvReader.readLine()) != null) {
            frames.add(FullPFeatureFrame.fromCSV(line));
        }
        csvReader.close();
        index = 0;
    }

    @Override
    public FullPFeatureFrame getFullFrame(int t) {
        return index < frames.size() ? frames.get(index++) : null;
    }

    @Override
    public int getMaxT() {
        return frames.size();
    }

}
