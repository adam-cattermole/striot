C|n1: nodeSource

C|n2: nodeLink (streamFilter . streamMap)

C|n3: nodeLink (streamMap . streamWindow)

C|n4: nodeSink

=>

C|n1: nodeSource

C|n2: nodeLink (streamMap . streamWindow . streamFilter . streamMap)

C|n4: nodeSink
