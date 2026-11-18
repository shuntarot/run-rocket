# make -C linux/cflush    copies the wrapper, ../rtl/linux_top.veryl, into
#                         rtl/, where its include picks up this core
#
# A copy, not a symbolic link: Veryl does not follow links when another
# project (a harness project) reads this one as a dependency.
rtl/linux_top.veryl: ../rtl/linux_top.veryl
	cp $< $@
