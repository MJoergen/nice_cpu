// Runs a log of writes (opm_model.py's read_log) through ymfm's YM2151,
// and prints each sample as opm_model.py does. opm_ymfm.py builds it
// against a copy of ymfm whose engine computes every channel in every
// sample, as the chip does, where ymfm leaves out a quiet channel.
//
// The writes of the timers' registers, 0x10, 0x11, 0x12, and 0x14, are
// dropped, as the synthesizer of doc/DEVICES.md §12 ignores them.

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "ymfm_opm.h"

int main(int argc, char **argv)
{
	if (argc != 2)
	{
		std::fprintf(stderr, "usage: opm_ymfm LOG\n");
		return 2;
	}
	FILE *f = std::fopen(argv[1], "r");
	if (f == nullptr)
	{
		std::perror(argv[1]);
		return 2;
	}
	ymfm::ymfm_interface intf;
	ymfm::ym2151 chip(intf);
	chip.reset();

	char line[256];
	long next = -1, count = 0;
	unsigned reg = 0, data = 0;
	long sample = 0;
	auto read_write = [&]() {
		next = -1;
		while (std::fgets(line, sizeof line, f) != nullptr)
		{
			char *hash = std::strchr(line, '#');
			if (hash != nullptr)
				*hash = 0;
			char word[32];
			if (std::sscanf(line, "%31s", word) != 1)
				continue;
			if (std::strcmp(word, "end") == 0)
			{
				std::sscanf(line, "%*s %ld", &count);
				continue;
			}
			std::sscanf(line, "%ld %x %x", &next, &reg, &data);
			return;
		}
	};
	read_write();
	// The count comes at the end of the log, so the writes are read first.
	struct entry { long n; unsigned reg, data; };
	entry *writes = nullptr;
	size_t nw = 0, cap = 0;
	while (next >= 0)
	{
		if (nw == cap)
		{
			cap = cap ? 2 * cap : 1024;
			writes = static_cast<entry *>(std::realloc(writes, cap * sizeof(entry)));
		}
		writes[nw++] = entry{next, reg, data};
		read_write();
	}
	std::fclose(f);

	size_t i = 0;
	for (sample = 0; sample < count; sample++)
	{
		if (i < nw && writes[i].n == sample)
		{
			unsigned r = writes[i].reg;
			if (r != 0x10 && r != 0x11 && r != 0x12 && r != 0x14)
			{
				chip.write_address(uint8_t(r));
				chip.write_data(uint8_t(writes[i].data));
			}
			i++;
		}
		ymfm::ym2151::output_data out;
		chip.generate(&out);
		std::printf("%d %d\n", int(out.data[0]), int(out.data[1]));
	}
	std::free(writes);
	return 0;
}
