import com.xilinx.rapidwright.device.*;
import com.xilinx.rapidwright.rwroute.*;
import com.xilinx.rapidwright.timing.delayestimator.*;
import java.io.*;
public class Price {
  public static void main(String[] a) throws Exception {
    Device d = Device.getDevice("xck26-sfvc784-2LV-c");
    DelayEstimatorBase<InterconnectInfo> est = new DelayEstimatorBase<>(d, new InterconnectInfo(), true, 0);
    try (BufferedReader r = new BufferedReader(new FileReader(a[0])); PrintWriter w = new PrintWriter(a[1])) {
      String l;
      while ((l = r.readLine()) != null) {
        String[] p = l.split("\t");
        if (p.length < 4) continue;
        int sum = 0, n = 0, miss = 0;
        for (String nn : p[3].split(" ")) {
          Node node = d.getNode(nn);
          if (node == null) { miss++; continue; }
          n++;
          if (RouteNode.isExitNode(node)) sum += est.getDelayOf(node);
        }
        w.println(p[0] + "\t" + sum + "\t" + n + "\t" + miss + "\t" + p[1] + "\t" + p[2]);
      }
    }
  }
}
