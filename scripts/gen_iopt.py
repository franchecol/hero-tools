
#
# This script sets-up a TRANSPARENT page table for the IOMMU. It can map multiple regions
# identified by --region and locate the page table at --loc
# Exemple: python3 gen_iopt.py --loc 0xF0000000 --region 0xC0000000/0xD0000000 0x78000000/0x78400000
#

import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--loc'   , dest='loc'     , type=str, help='location where to place the iopt')
parser.add_argument('--region', dest='regions' , nargs='+', type=str, help='start region to map')

args = parser.parse_args()

def align_up(addr, res, boundary=0x1000):
    if addr % boundary == 0:
        return addr, res
    return addr + boundary - (addr % boundary), res + (boundary - (addr % boundary)) * (0).to_bytes(1, 'little')

def get_page_idx(addr, lvl):
    return (addr >> (12+9*(3-1-lvl))) & 0b111111111

class DDTE:
    def __init__(self, ppn, location):
        self.ppn = ppn
        self.mode = 8
        self.location = location
    def to_byte(self):
        tc      = (1).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
        iohgatp = (0).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
        ta      = (0).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
        fsc     = (self.ppn).to_bytes(4, 'little') + (self.mode << 28).to_bytes(4, 'little')
        return tc + iohgatp + ta + fsc

class PTE:
    def __init__(self, level, point_idx, ppn, location=-1):
        self.level = level
        self.point_idx = point_idx
        self.ppn = ppn
        self.location = location
        self.flags = 0b1 if level != 2 else 0b11111
    def __str__(self):
        return f'{self.point_idx}'
    def to_byte(self):
        return ((self.ppn << 10) | self.flags).to_bytes(8, 'little')

class MemRegion:
    def __init__(self, begin, end):
        self.begin = begin
        self.end = end
        self.page_size = 0x1000
        self.pages = {0:[], 1:[], 2:[]}
        self.create_pages()

    def create_pages(self):
        assert self.begin % self.page_size == 0, "Non page aligned boundary region"
        assert self.end   % self.page_size == 0, "Non page aligned boundary region"
        idx = 0
        # Allocate first pages
        if ((self.begin >> 12) & 0b111111111) != 0:
            self.pages[1].append(PTE(1, idx, -1))
        if ((self.begin >> (12+9)) & 0b111111111) != 0:
            self.pages[0].append(PTE(0, idx, -1))

        for addr in range(self.begin, self.end, self.page_size):
            if ((addr >> 12) & 0b111111111) == 0:
                self.pages[1].append(PTE(1, idx, -1))    
                if ((addr >> (12+9)) & 0b111111111) == 0:
                    self.pages[0].append(PTE(0, idx, -1))
            self.pages[2].append(PTE(2, -1, addr >> 12))
            idx += 1

    def place_ptes(self, address):
        res = bytearray()
        for pte in self.pages[2]:
            pte.location = address
            address += 8
            res = res + pte.to_byte()
        # Page re-align
        address, res = align_up(address, res)
        for pte in self.pages[1]:
            pte.location = address
            pte.ppn = self.pages[2][pte.point_idx].location >> 12
            address += 8
            res = res + pte.to_byte()
        for pte in self.pages[0]:
            pte.ppn = self.pages[1][pte.point_idx].location >> 12
        # Page re-align
        address, res = align_up(address, res)
        return address, res


location = int(args.loc, 16)
all_bytes = bytearray()

regions = []

for region_def in args.regions:
    begin  = int(region_def.split('/')[0], 16)
    end    = int(region_def.split('/')[1], 16)
    region = MemRegion(begin, end)
    location, res_bytes = region.place_ptes(location)
    all_bytes = all_bytes + res_bytes
    regions.append(region)

root_ptes = []

for i in range(512):
    root_ptes.append(PTE(0, 0, 0, location))
    location += 8

for region in regions:
    for page in region.pages[0]:
        # Get the address of a leaf to know our own offset
        leaf_addr = region.pages[2][region.pages[1][page.point_idx].point_idx].ppn << 12
        page_idx = leaf_addr >> (12 + 9 + 9)
        assert root_ptes[page_idx].ppn == 0, "Different regions can not share any PTEs"
        page.location = root_ptes[page_idx].location
        root_ptes[page_idx] = page

for pte in root_ptes:
    all_bytes = all_bytes + pte.to_byte()

# Now do ddt
location, all_bytes = align_up(location, all_bytes)

dtte = DDTE(root_ptes[0].location >> 12, location)

all_bytes = all_bytes + dtte.to_byte()

f = open("output.bin", "wb")
f.write(all_bytes)
f.close()

ddtp_ppn_lo = (((dtte.location >> 12) & (0b1111111111111111111111)) << 10) | 2

gdb_script = \
"""
restore output.bin binary 0x%x
set *0x2000a010 = 0x%x
""" % (int(args.loc, 16), ddtp_ppn_lo)

f = open("output.gdb", "w")
f.write(gdb_script)
f.close()

print("Done, ddt is at 0x%x" % dtte.location)
