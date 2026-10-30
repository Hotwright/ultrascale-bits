import csv
out = open("arcs.csv", "w")
w = csv.writer(out)
w.writerow(["net","sx","sy","dx","dy","spin","dpin","delay","pred","stype","dtype"])
for name, net in ctx.nets:
    drv = net.driver
    if drv.cell is None or drv.cell.bel is None: continue
    if len(net.users) > 200: continue  # clocks, constants
    sl = ctx.getBelLocation(drv.cell.bel)
    for u in net.users:
        if u.cell is None or u.cell.bel is None: continue
        dl = ctx.getBelLocation(u.cell.bel)
        try:
            d = ctx.getNetinfoRouteDelay(net, u)
        except Exception as e:
            continue
        try:
            p = ctx.predictArcDelay(net, u)
        except Exception:
            p = -1
        w.writerow([name, sl.x, sl.y, dl.x, dl.y, drv.port, u.port, d, p, drv.cell.type, u.cell.type])
out.close()
