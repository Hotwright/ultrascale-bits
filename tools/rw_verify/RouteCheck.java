package dev.fpga.rwverify;

import com.xilinx.rapidwright.device.Device;
import com.xilinx.rapidwright.device.Node;
import com.xilinx.rapidwright.device.PIP;
import com.xilinx.rapidwright.device.Tile;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.*;

/**
 * Checks nextpnr's routing against RapidWright's device model -- independently
 * of the chipdb nextpnr routed on. Input: extract_routes.py's records.
 *
 * For every net:
 *  1. every tile pip exists in RapidWright (either direction for bidirectional);
 *  2. every pip's start node is reached, from a source (a route root, or the
 *     tile-wire end of a site pip driving out of a site) or from another pip's
 *     end node -- otherwise nextpnr thought two wires were one node that are not;
 *  3. every sink (tile-wire end of a site pip driving into a site) is reached;
 *  4. no node is used by two nets (a short on silicon). Constant wires
 *     (VCC_WIRE / GND_WIRE) are exempt.
 *
 * usage: RouteCheck <part> <routes.txt> [max reports per class]
 */
public class RouteCheck {
    static Device dev;
    static Map<Long, Tile> tiles = new HashMap<>();
    static Map<String, Set<String>> pipsByType = new HashMap<>();

    static Tile tile(int x, int y) { return tiles.get(((long) x << 32) | y); }

    static Node node(Tile t, String wire) {
        Integer w = t.getWireIndex(wire);
        if (w == null || w < 0) return null;
        return Node.getNode(t, w);
    }

    static boolean pipExists(Tile t, String src, String dst) {
        Set<String> s = pipsByType.computeIfAbsent(t.getTileTypeEnum().name(), k -> {
            Set<String> ss = new HashSet<>();
            for (PIP p : t.getPIPs()) {
                ss.add(p.getStartWireName() + ">" + p.getEndWireName());
                if (p.isBidirectional()) ss.add(p.getEndWireName() + ">" + p.getStartWireName());
            }
            return ss;
        });
        return s.contains(src + ">" + dst);
    }

    static boolean isConst(Node n) {
        String s = n.getWireName();
        return s.contains("VCC_WIRE") || s.contains("GND_WIRE");
    }

    public static void main(String[] args) throws Exception {
        dev = Device.getDevice(args[0]);
        int maxRep = args.length > 2 ? Integer.parseInt(args[2]) : 20;
        for (Tile t : dev.getAllTiles()) tiles.put(((long) t.getColumn() << 32) | t.getRow(), t);
        Tile probe = tile(160, 144);
        System.out.println("grid (160,144) -> " + (probe == null ? "null" : probe.getName()));

        Map<Node, String> owner = new HashMap<>();
        int nets = 0, pips = 0, noPip = 0, noWire = 0, broken = 0, unreached = 0, shorts = 0;
        Map<String, Integer> classCount = new HashMap<>();
        BufferedReader br = new BufferedReader(new FileReader(args[1]));
        String line, net = null;
        List<String[]> recs = new ArrayList<>();
        List<String> lines = new ArrayList<>();
        while ((line = br.readLine()) != null) lines.add(line);
        lines.add("N <end>");
        for (String l : lines) {
            if (l.startsWith("N ")) {
                if (net != null) {
                    // ---- check one net ----
                    nets++;
                    Set<Node> reached = new HashSet<>(), used = new HashSet<>();
                    List<Node[]> pl = new ArrayList<>();
                    List<String> plName = new ArrayList<>();
                    List<Node> sinks = new ArrayList<>();
                    List<String> sinkName = new ArrayList<>();
                    for (String[] r : recs) {
                        Tile t = tile(Integer.parseInt(r[1]), Integer.parseInt(r[2]));
                        if (t == null) { noWire++; continue; }
                        if (r[0].equals("R")) {
                            if (!r[3].contains(".")) { Node n = node(t, r[3]); if (n != null) { reached.add(n); used.add(n); } }
                        } else if (r[0].equals("S")) {
                            String[] ds = r[3].split("/");
                            if (ds.length == 2) {
                                if (!ds[0].contains(".")) { Node n = node(t, ds[0]); if (n != null) { reached.add(n); used.add(n); } }
                                if (!ds[1].contains(".")) { Node n = node(t, ds[1]); if (n != null) { sinks.add(n); sinkName.add(t.getName() + "/" + ds[1]); used.add(n); } }
                            }
                        } else if (r[0].equals("P")) {
                            String dst = r[3], src = r[4];
                            if (src.startsWith("PSEUDO_")) {   // nextpnr's constant-driver pseudo pip: its dst is a source
                                Node n = node(t, dst); if (n != null) { reached.add(n); used.add(n); }
                                continue;
                            }
                            pips++;
                            if (!pipExists(t, src, dst)) {
                                noPip++;
                                if (noPip <= maxRep) System.out.println("NO-PIP " + net + " " + t.getName() + " " + src + " -> " + dst);
                            }
                            Node a = node(t, src), b = node(t, dst);
                            if (a == null || b == null) {
                                noWire++;
                                if (noWire <= maxRep) System.out.println("NO-WIRE " + net + " " + t.getName() + " " + src + " / " + dst);
                                continue;
                            }
                            pl.add(new Node[]{a, b});
                            plName.add(t.getName() + " " + src + " -> " + dst);
                            used.add(a); used.add(b);
                        }
                    }
                    boolean changed = true;
                    boolean[] done = new boolean[pl.size()];
                    while (changed) {
                        changed = false;
                        for (int i = 0; i < pl.size(); i++)
                            if (!done[i] && reached.contains(pl.get(i)[0])) { done[i] = true; reached.add(pl.get(i)[1]); changed = true; }
                    }
                    for (int i = 0; i < pl.size(); i++)
                        if (!done[i]) {
                            broken++;
                            if (broken <= maxRep) System.out.println("BROKEN " + net + " " + plName.get(i) + "  (start node " + pl.get(i)[0] + " not reached)");
                        }
                    for (int i = 0; i < sinks.size(); i++)
                        if (!reached.contains(sinks.get(i))) {
                            unreached++;
                            if (unreached <= maxRep) System.out.println("UNREACHED-SINK " + net + " " + sinkName.get(i) + " node " + sinks.get(i));
                        }
                    for (Node n : used) {
                        if (isConst(n)) continue;
                        String o = owner.putIfAbsent(n, net);
                        if (o != null && !o.equals(net)) {
                            shorts++;
                            if (shorts <= maxRep) System.out.println("SHORT node " + n + " used by " + o + " AND " + net);
                        }
                    }
                }
                net = l.substring(2);
                recs.clear();
            } else if (!l.isBlank()) {
                String[] r = l.split(" ", 5);
                if (r.length >= 4) recs.add(r);
            }
        }
        System.out.printf("nets %d, tile pips %d | missing pips %d, missing wires %d, broken pips %d, unreached sinks %d, shorted nodes %d%n",
                nets, pips, noPip, noWire, broken, unreached, shorts);
    }
}
