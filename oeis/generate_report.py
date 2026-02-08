#!/usr/bin/env python3
"""Generate a PDF report documenting the computation of A174511(14) = 7766."""

from fpdf import FPDF
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "A174511_14_computation_report.pdf")


class Report(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.cell(0, 8, "Computation of A174511(14) = 7,766", align="C", new_x="LMARGIN", new_y="NEXT")
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(2)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    def section_title(self, title):
        self.set_font("Helvetica", "B", 13)
        self.ln(4)
        self.cell(0, 8, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def subsection_title(self, title):
        self.set_font("Helvetica", "B", 11)
        self.ln(2)
        self.cell(0, 7, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def body_text(self, text):
        self.set_font("Helvetica", "", 10)
        self.multi_cell(0, 5, text)
        self.ln(1)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        indent = 15
        self.cell(indent, 5, "  -  ", new_x="RIGHT", new_y="TOP")
        self.multi_cell(self.w - self.r_margin - self.get_x(), 5, text)
        self.set_x(self.l_margin)

    def code_block(self, text):
        self.set_font("Courier", "", 9)
        self.set_fill_color(240, 240, 240)
        for line in text.strip().split("\n"):
            self.cell(0, 4.5, "  " + line, fill=True, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def table_row(self, cells, bold=False, fill=False):
        style = "B" if bold else ""
        self.set_font("Helvetica", style, 10)
        if fill:
            self.set_fill_color(230, 230, 240)
        col_widths = [25, 55, 55, 55]
        for i, cell in enumerate(cells):
            w = col_widths[i] if i < len(col_widths) else 45
            self.cell(w, 6, str(cell), border=1, fill=fill, align="C")
        self.ln()


def build_report():
    pdf = Report()
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    # Title
    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(0, 12, "Computation and Verification of A174511(14)", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 8, "Number of Isomorphism Types of Subgroups of S_14", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 10, "Result: A174511(14) = 7,766", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(0, 6, "Jeffrey Yan  |  February 2026", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(6)

    # ================================================================
    pdf.section_title("1. Introduction")
    pdf.body_text(
        "OEIS sequence A174511 counts the number of isomorphism types of subgroups of the "
        "symmetric group S_n. Two subgroups are considered isomorphic if they are isomorphic "
        "as abstract groups, not as permutation groups. This report documents the computation "
        "of a(14) = 7,766, extending the sequence beyond the previously known a(13) = 3,845."
    )
    pdf.body_text(
        "The computation was carried out using GAP (Groups, Algorithms, Programming) version "
        "4.15.1 on a Windows system with Cygwin and WSL environments. The result was verified "
        "through four independent rounds of checking (original computation, double check, "
        "triple check, and quadruple check)."
    )

    # ================================================================
    pdf.section_title("2. Known Values")
    pdf.body_text("The complete sequence A174511 through n = 14:")
    pdf.ln(1)

    values = [
        (1, 1), (2, 2), (3, 4), (4, 9), (5, 16), (6, 29), (7, 55),
        (8, 137), (9, 241), (10, 453), (11, 894), (12, 2065), (13, 3845), (14, 7766)
    ]
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(25, 6, "n", border=1, align="C", fill=False)
    pdf.cell(50, 6, "a(n)", border=1, align="C")
    pdf.cell(35, 6, "Ratio", border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 10)
    for i, (n, a) in enumerate(values):
        ratio = f"{a / values[i-1][1]:.3f}" if i > 0 else "-"
        pdf.cell(25, 5.5, str(n), border=1, align="C")
        pdf.cell(50, 5.5, f"{a:,}", border=1, align="C")
        pdf.cell(35, 5.5, ratio, border=1, align="C")
        pdf.ln()
    pdf.ln(2)
    pdf.body_text(
        "The ratio a(14)/a(13) = 2.020, consistent with the observed growth pattern of "
        "approximately 1.5x to 2.2x per increment."
    )

    # ================================================================
    pdf.section_title("3. Methodology")

    pdf.subsection_title("3.1 Overview")
    pdf.body_text(
        "The computation proceeds in three stages:\n"
        "  (1) Enumerate all conjugacy classes of subgroups of S_14.\n"
        "  (2) Classify each subgroup by abstract isomorphism type.\n"
        "  (3) Deduplicate to count distinct isomorphism types."
    )

    pdf.subsection_title("3.2 Stage 1: Conjugacy Class Enumeration")
    pdf.body_text(
        "We first computed A000638(14) = 75,154, the number of conjugacy classes of subgroups "
        "of S_14. This was done via maximal subgroup decomposition: every subgroup of S_14 is "
        "contained in at least one maximal subgroup. The maximal subgroups of S_14 are:"
    )
    pdf.bullet("7 intransitive subgroups: S_k x S_(14-k) for k = 1..7")
    pdf.bullet("2 wreath products: S_2 wr S_7 and S_7 wr S_2")
    pdf.bullet("Primitive groups of degree 14 (from GAP's primitive groups library)")
    pdf.bullet("The alternating group A_14")
    pdf.ln(1)
    pdf.body_text(
        "Subgroup lattices of each maximal subgroup were computed in parallel (11 workers), "
        "producing 600,634 candidate subgroups. These were deduplicated using invariant-based "
        "bucketing and pairwise S_14-conjugacy testing, yielding 75,154 conjugacy class "
        "representatives. This matches the known value of A000638(14)."
    )

    pdf.subsection_title("3.3 Stage 2: Isomorphism Type Classification")
    pdf.body_text(
        "Each of the 75,154 conjugacy class representatives was classified into one of two categories:"
    )
    pdf.bullet(
        "IdGroup-compatible (order < 2,000 and not in {512, 768, 1024, 1536}): "
        "64,467 groups, yielding 4,602 unique IdGroup types."
    )
    pdf.bullet(
        "Large groups (order >= 2,000 or in {512, 768, 1024, 1536}): "
        "10,687 groups requiring isomorphism deduplication."
    )
    pdf.ln(1)
    pdf.body_text(
        "GAP's IdGroup function assigns a canonical identifier [order, id] to groups of "
        "order less than 2,000 (excluding orders 512, 768, 1024, and 1536 where the small "
        "groups library is incomplete). Groups with the same IdGroup are isomorphic."
    )

    pdf.subsection_title("3.4 Stage 3: Large Group Deduplication")
    pdf.body_text(
        "The 10,687 large groups were deduplicated using a multi-level approach:"
    )
    pdf.bullet(
        "Invariant bucketing: Groups were sorted into buckets by a signature key "
        "[order, derived_size, conjugacy_classes, derived_length, abelian_invariants] "
        "combined with an element-order/fixed-point histogram. Groups in different "
        "buckets are guaranteed non-isomorphic."
    )
    pdf.bullet(
        "Direct product decomposition: 7,431 of the 10,687 groups decompose as direct "
        "products of smaller groups. Factor-level isomorphism testing (comparing sorted "
        "factor IdGroups via bipartite matching) replaces expensive full-group tests."
    )
    pdf.bullet(
        "2-group testing: 336 groups of order 512 were tested using the ANUPQ package's "
        "IsIsomorphicPGroup function, which is optimized for p-groups."
    )
    pdf.bullet(
        "Full isomorphism testing: The remaining non-DP, non-2-group buckets (2,095 groups "
        "across 508 buckets) used GAP's IsomorphismGroups for pairwise comparison."
    )
    pdf.ln(1)
    pdf.body_text(
        "Result: 10,687 large groups deduplicated to 3,164 unique isomorphism types."
    )

    # ================================================================
    pdf.add_page()
    pdf.section_title("4. Result Breakdown")
    pdf.body_text("The final count of A174511(14) = 7,766 is composed of:")
    pdf.ln(1)

    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(90, 6, "Category", border=1, align="C")
    pdf.cell(30, 6, "Groups", border=1, align="C")
    pdf.cell(30, 6, "Types", border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 10)
    rows = [
        ("IdGroup-compatible", "64,467", "4,602"),
        ("Large: Direct products", "7,431", "2,269"),
        ("Large: 2-groups (order 512)", "336", "10"),
        ("Large: Regular (non-DP, non-2-group)", "2,908", "884"),
        ("Large: Difficult bucket (order 2,592)", "4", "1"),
        ("TOTAL", "75,154 *", "7,766"),
    ]
    for i, (cat, groups, types) in enumerate(rows):
        bold = i == len(rows) - 1
        if bold:
            pdf.set_font("Helvetica", "B", 10)
        pdf.cell(90, 5.5, cat, border=1)
        pdf.cell(30, 5.5, groups, border=1, align="R")
        pdf.cell(30, 5.5, types, border=1, align="R")
        pdf.ln()
        if bold:
            pdf.set_font("Helvetica", "", 10)
    pdf.ln(1)
    pdf.set_font("Helvetica", "I", 9)
    pdf.cell(0, 5, "* 75,154 = A000638(14), the number of conjugacy classes of subgroups of S_14.",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(3)

    # ================================================================
    pdf.section_title("5. Verification History")

    pdf.subsection_title("5.1 Original Computation (January 2026)")
    pdf.body_text(
        "The initial computation used the partition-based method from a174511.g, processing "
        "all 34 integer partitions of 14. Groups were classified by IdGroup where possible "
        "and deduplicated using invariant-based bucketing with CompareByFactorsV3 for direct "
        "products and IsomorphismGroups for non-decomposable groups."
    )

    pdf.subsection_title("5.2 Double Check (January 2026)")
    pdf.body_text(
        "An independent 6-way parallel computation re-covered all 34 partitions (3,878 "
        "group combinations). Cross-deduplication against S_13 large groups identified "
        "758 duplicates. A bug in the original CompareByFactorsV3 algorithm was discovered: "
        "when groups had two semidirect factors in the old ambiguousFactorGens format, only "
        "one factor was compared. This caused an undercount of 1 group."
    )

    pdf.subsection_title("5.3 Triple Check (February 2026)")
    pdf.body_text(
        "A completely independent approach using conjugacy class representatives from "
        "A000638(14) = 75,154. The factorGens refactor replaced the buggy ambiguousFactorGens "
        "with positionally-aligned factorGens for ALL direct product factors. This found "
        "11 additional IdGroup types (1 of order 128 + 10 of order 256) that were lost during "
        "the original merge. Result: 4,602 + 3,164 = 7,766."
    )

    pdf.subsection_title("5.4 Quadruple Check (February 2026)")
    pdf.body_text(
        "The quadruple check independently verified the triple check's 3,164 large group "
        "representatives using two completely different approaches:"
    )
    pdf.ln(1)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, 5, "Phase 1: Fresh DP Deduplication (Factor IdGroup Canonicalization)",
             new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.body_text(
        "Instead of pairwise bipartite factor matching (CompareByFactorsV3), a canonical key "
        "was computed for each direct product group by taking the sorted list of per-factor "
        "IdGroups. Two DP groups are isomorphic iff their sorted factor IdGroup lists match. "
        "For factors without IdGroup (order 512, 1024, etc.), extended invariants were used "
        "with fallback to pairwise IsomorphismGroups on individual factors. "
        "Result: 2,271 DP reps (2 of which overlap with regular buckets in the triple check's "
        "partitioning). Cross-check: 2,271 + 10 + 884 + 1 - 2 = 3,164."
    )
    pdf.ln(1)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, 5, "Phase 2: Non-DP Bucket Verification",
             new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.body_text(
        "For every non-DP bucket from the triple check (508 multi-group buckets + 6 2-group "
        "buckets), the quadruple check verified: (a) all representatives are mutually "
        "non-isomorphic, and (b) every non-representative is isomorphic to at least one "
        "representative. Six parallel Cygwin workers handled regular buckets; one WSL worker "
        "with ANUPQ handled 2-group buckets. Two hard buckets with expensive isomorphism tests "
        "(order 2,592 and order 10,368) were re-verified using saved explicit homomorphism proofs."
    )
    pdf.ln(1)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, 5, "Quadruple Check Result: ALL PHASES PASSED", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.ln(2)

    results = [
        ("Phase 1 (DP)", "2,271 fresh reps", "PASS"),
        ("Phase 2B Regular (6 workers)", "508 buckets, 0 errors", "PASS"),
        ("Phase 2B 2-groups (1 worker)", "6 buckets, 0 errors", "PASS"),
        ("Phase 2C Difficult proof", "4 groups -> 1 rep", "PASS"),
        ("Phase 2C Hard proof", "8 groups -> 1 rep", "PASS"),
    ]
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(70, 6, "Phase", border=1, align="C")
    pdf.cell(70, 6, "Detail", border=1, align="C")
    pdf.cell(30, 6, "Result", border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 10)
    for phase, detail, result in results:
        pdf.cell(70, 5.5, phase, border=1)
        pdf.cell(70, 5.5, detail, border=1, align="C")
        pdf.cell(30, 5.5, result, border=1, align="C")
        pdf.ln()
    pdf.ln(3)

    # ================================================================
    pdf.section_title("6. Correction History")
    pdf.body_text(
        "The value of a(14) underwent several corrections during computation:"
    )
    corrections = [
        ("7,095", "Initial partition-based computation"),
        ("7,739", "After fixing missing partition [8,2,2,2]"),
        ("7,740", "After finding 1 additional group from DC verification"),
        ("7,754", "After cross-deduplication corrections"),
        ("7,756", "After additional bucket analysis"),
        ("7,755", "After fixing CompareByFactorsV3 bug (two-semidirect-factor case)"),
        ("7,766", "Triple check: 11 missing IdGroup types found (final, verified by quadruple check)"),
    ]
    for val, desc in corrections:
        pdf.bullet(f"{val}: {desc}")
    pdf.ln(2)
    pdf.body_text(
        "The final value of 7,766 has been independently confirmed by the quadruple check "
        "using a completely different DP deduplication algorithm and exhaustive verification "
        "of all non-DP isomorphism results."
    )

    # ================================================================
    pdf.add_page()
    pdf.section_title("7. Computational Resources")
    pdf.body_text(
        "The computation was performed on a single Windows machine with the following setup:"
    )
    pdf.bullet("GAP 4.15.1 (via Cygwin bash) for group-theoretic computations")
    pdf.bullet("WSL (Windows Subsystem for Linux) with ANUPQ package for 2-group testing")
    pdf.bullet("Python 3.11 for orchestration, parallel worker management, and data processing")
    pdf.bullet("Up to 11 parallel GAP workers, each allocated 8-50 GB memory")
    pdf.ln(1)
    pdf.body_text("Approximate wall-clock times for major computation phases:")
    pdf.bullet("A000638(14) = 75,154 conjugacy classes: ~12 hours (11 parallel workers)")
    pdf.bullet("IdGroup classification (64,467 groups): ~2 hours (8 parallel workers)")
    pdf.bullet("Large group deduplication (10,687 groups): ~6 hours (12 parallel workers)")
    pdf.bullet("Quadruple check verification: ~6 hours (8 parallel workers)")

    # ================================================================
    pdf.section_title("8. Software and Reproducibility")
    pdf.body_text(
        "All computation code is available at: https://github.com/jeff87654/symmetric-group-subgroups"
    )
    pdf.ln(1)
    pdf.body_text("Key files:")
    pdf.bullet("triple_check/process_s14_subgroups.g - Main conjugacy class processing")
    pdf.bullet("triple_check/dedupe/ - Isomorphism deduplication pipeline")
    pdf.bullet("triple_check/quad_check/ - Quadruple check verification")
    pdf.bullet("Partition/a174511.g - Original partition-based algorithm")
    pdf.bullet("Partition/tests/test_groups_static.g - 41-group validation test suite")
    pdf.ln(1)
    pdf.body_text(
        "The computation can be independently verified by: (1) computing A000638(14) = 75,154 "
        "conjugacy class representatives using ConjugacyClassesSubgroups(SymmetricGroup(14)), "
        "then (2) classifying each representative by IdGroup where applicable and deduplicating "
        "the remainder by isomorphism testing."
    )

    # ================================================================
    pdf.section_title("9. Related Sequences")
    pdf.body_text("This computation also verified/produced values for related OEIS sequences:")
    pdf.ln(1)
    pdf.bullet("A000638(14) = 75,154 (conjugacy classes of subgroups of S_14) - matches known value")
    pdf.bullet("A174511(14) = 7,766 (isomorphism types of subgroups of S_14) - NEW")
    pdf.ln(2)

    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 10, "Conclusion: A174511(14) = 7,766", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    pdf.set_font("Helvetica", "", 10)
    pdf.body_text(
        "The value a(14) = 7,766 has been computed via conjugacy class enumeration and "
        "isomorphism deduplication, and independently verified through four rounds of "
        "checking using multiple algorithms. The result is 4,602 IdGroup types plus "
        "3,164 large group representatives = 7,766 total isomorphism types."
    )

    pdf.output(OUTPUT_PATH)
    print(f"Report generated: {OUTPUT_PATH}")


if __name__ == "__main__":
    build_report()
