import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

import java.io.IOException;

public class WordCountApplication {
    public static void main(String[] args) throws IOException, ClassNotFoundException, InterruptedException {
        Configuration hadoopConfiguration = new Configuration();
        Job hadoopJob = Job.getInstance(hadoopConfiguration, "WordCount");
        hadoopJob.setJarByClass(WordCountApplication.class);
        hadoopJob.setMapperClass(WordCountMapper.class);
        hadoopJob.setCombinerClass(WordCountReducer.class);
        hadoopJob.setReducerClass(WordCountReducer.class);
        hadoopJob.setOutputKeyClass(Text.class);
        hadoopJob.setOutputValueClass(IntWritable.class);
        FileInputFormat.addInputPath(hadoopJob, new Path(args[0]));
        FileOutputFormat.setOutputPath(hadoopJob, new Path(args[1]));
        System.exit(hadoopJob.waitForCompletion(true) ? 0 : 1);
    }
}
