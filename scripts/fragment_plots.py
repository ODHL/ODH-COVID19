import pandas as pd
import matplotlib.pyplot as plt
import sys
import seaborn as sns
import warnings

#suppress any warnings
def fxn():
    warnings.warn("deprecated", DeprecationWarning)

with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    fxn()

warnings.simplefilter(action='ignore', category=FutureWarning)

#fragment length text file
frag_file=sys.argv[1]

#read in file, set columns
frag_df = pd.read_csv(frag_file,sep="\t",header=None)
frag_df.columns = ["sample_id", "fragment_length", "batch_id"]

#set max
max_value=frag_df["fragment_length"].max() + 5

#set id to character
frag_df['sample_id'] = frag_df.sample_id.astype(str)

#create facetgrid
plot = sns.FacetGrid(frag_df, col="batch_id", height=2, aspect=10, col_wrap = 1,sharex = False, sharey = False)

#create barplot: x=sampleid, y=frag length
plot1 = plot.map(sns.barplot,
                 'sample_id', 
                 'fragment_length').fig.subplots_adjust(wspace=0.5, hspace=12)

#rotate x axis labels, shrink font
for axes in plot.axes.flat:
    _ = axes.set_xticklabels(axes.get_xticklabels(), rotation=90, Fontsize=5)

#add labels to plot
for ax in plot.axes:
    for p in ax.patches:
             ax.annotate("%.0f" % p.get_height(), (p.get_x() + p.get_width() / 2., p.get_height()),
                 ha='center', va='center', fontsize=5, color='black', xytext=(0, 5),
                 textcoords='offset points')

#remove x axis title
plot.set(xlabel=None)

#add title to plot
plot.fig.suptitle('Average Fragment Length by SampleID')

#reduce margins
plt.tight_layout()

#for testing, show
#plt.show()

#save plot to file
file_save = sys.argv[2]
plt.savefig(file_save)
