import pandas as pd
import matplotlib.pyplot as plt
import sys

#fragment length text file
frag_file=sys.argv[1]

#read in file, set columns
frag_df = pd.read_csv(frag_file,sep="\t",header=None)
frag_df.columns = ["sample_id", "fragment_length", "batch"]

#set max
max_value=frag_df["fragment_length"].max() + 5

#set id to character
frag_df['sample_id'] = frag_df.sample_id.astype(str)

#create plot, add titles
frag_df.plot.bar(x="sample_id",y="fragment_length",rot=90,legend=False,ylim=(0,max_value))
plt.title('Average fragment length by sample ID')
plt.tight_layout()

#save plot to file
file_save = sys.argv[2]
plt.savefig(file_save)
