"""Figures and the animated GIF for the README, from results/.

    python scripts/make_figures.py

The simulation itself runs in Julia (scripts/run_simulation.jl); this script
only reads its CSV output, so it runs in seconds on a laptop. Needs numpy,
pandas, matplotlib and pillow.
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from style import INK, GOLD, BLUE, GREY, LIGHT, DARK_GOLD, SUBTLE, apply_style, frame

ROOT = Path(__file__).resolve().parents[1]
RES, FIGS = ROOT / "results", ROOT / "figures"
FIGS.mkdir(exist_ok=True)
TRUE_ATE = 2.0
apply_style()

PALE_BLUE = "#8E9BE6"
# Three families: adjusts for all 14 covariates (blue), C-TMLE (indigo), oracle (marigold).
STYLES = {
    "Naive difference in means":     dict(short="Naive",                colour=GREY,      ls="-"),
    "One-step (AIPW)":               dict(short="AIPW",                 colour=BLUE,      ls="-"),
    "TMLE (weighted)":               dict(short="TMLE\n(weighted)",     colour=BLUE,      ls="--"),
    "TMLE (unweighted)":             dict(short="TMLE\n(unweighted)",   colour=PALE_BLUE, ls=":"),
    "C-TMLE (greedy)":               dict(short="C-TMLE\n(greedy)",     colour=INK,       ls="-"),
    "C-TMLE (adaptive correlation)": dict(short="C-TMLE\n(adaptive)",   colour=INK,       ls="--"),
    "Oracle TMLE":                   dict(short="Oracle",               colour=GOLD,      ls="-"),
}
ORDER = list(STYLES)
FAMILY = {"Naive difference in means": "none", "One-step (AIPW)": "all", "TMLE (weighted)": "all",
          "TMLE (unweighted)": "all", "C-TMLE (greedy)": "ctmle", "C-TMLE (adaptive correlation)": "ctmle",
          "Oracle TMLE": "oracle"}
FAMILY_LABEL = {"none": ("no adjustment", GREY), "all": ("adjusts for all 14", BLUE),
                "ctmle": ("chooses what to adjust for", INK), "oracle": ("knows the true roles", DARK_GOLD)}

results = pd.read_csv(RES / "simulation_results.csv")
summary = pd.read_csv(RES / "summary.csv")
LEVELS = sorted(summary.instrument.unique())


def stat(level: float, estimator: str, col: str) -> float:
    row = summary[(summary.instrument == level) & (summary.estimator == estimator)]
    return float(row[col].iloc[0])


# ── Figure 1: accuracy, interval width and coverage across instrument strengths ──────────────
def plot_by_strength() -> None:
    panels = [("rmse", "Error (RMSE)", (0, 0.3), None),
              ("median_ci_width", "Median 95% interval width", (0, 0.6), None),
              ("coverage", "95% interval coverage (dotted: target)", (0.3, 1.02), 0.95)]
    shown = [e for e in ORDER if e != "Naive difference in means"]
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.9))
    fig.subplots_adjust(top=0.7, wspace=0.28, left=0.05, right=0.99)
    for ax, (col, title, ylim, ref) in zip(axes, panels):
        ax.grid(axis="y", color=LIGHT, lw=1)
        ax.grid(axis="x", visible=False)
        if ref is not None:
            ax.axhline(ref, color=GREY, lw=1, ls=(0, (2, 2)))
        for est in shown:
            st = STYLES[est]
            s = summary[summary.estimator == est].sort_values("instrument")
            y = s[col].to_numpy()
            yc = np.clip(y, *ylim)
            lw = 2.6 if est in ("C-TMLE (greedy)", "One-step (AIPW)", "Oracle TMLE") else 1.8
            ax.plot(s.instrument, yc, color=st["colour"], ls=st["ls"], lw=lw, marker="o", ms=4,
                    mfc=st["colour"], mec="white", mew=0.6, zorder=3)
            for x, v in zip(s.instrument, y):
                if v > ylim[1]:
                    ax.annotate(f"off scale: {v:.2f} ↑", (x, ylim[1]), xytext=(-10, -14), textcoords="offset points",
                                ha="right", va="top", fontsize=8.5, color=st["colour"], fontweight="bold")
        ax.set_ylim(*ylim)
        ax.set_xticks(LEVELS)
        ax.set_xlabel("Instrument strength")
        ax.set_title(title)
    axes[2].yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0, decimals=0))

    handles = [Line2D([], [], color=STYLES[e]["colour"], ls=STYLES[e]["ls"], lw=2.2,
                      label=STYLES[e]["short"].replace("\n", " ")) for e in shown]
    fig.legend(handles=handles, loc="lower left", bbox_to_anchor=(0.0, 0.775), ncol=6, frameon=False,
               fontsize=9.5, handlelength=2.6, columnspacing=1.6)
    frame(fig, "As instruments get stronger, adjusting for everything costs accuracy; C-TMLE barely notices",
          "Blue: estimators that adjust for all 14 covariates. Indigo: C-TMLE, which chooses what to adjust for. "
          "Marigold: an oracle\nthat knows which covariates are confounders. The naive difference in means "
          "(error 0.7 to 1.3) is off the scale.")
    fig.savefig(FIGS / "accuracy_by_strength.png")
    plt.close(fig)
    print("Saved accuracy_by_strength.png")


# ── Figures 2 and 3: estimates from every dataset at one strength ─────────────────────────────
YLIM = (-1.0, 5.0)


def strip(ax, level: float, seed: int = 1) -> None:
    rng = np.random.default_rng(seed)
    d = results[results.instrument == level]
    ax.grid(axis="y", color=LIGHT, lw=1)
    ax.grid(axis="x", visible=False)
    ax.axhline(TRUE_ATE, color=GOLD, lw=2, zorder=1)
    for i, est in enumerate(ORDER):
        st = STYLES[est]
        y = d.loc[d.estimator == est, "estimate"].to_numpy()
        y = y[np.isfinite(y)]
        x = i + rng.uniform(-0.22, 0.22, len(y))
        inside = (y >= YLIM[0]) & (y <= YLIM[1])
        colour = PALE_BLUE if est == "TMLE (unweighted)" else st["colour"]
        ax.scatter(x[inside], y[inside], s=16, color=colour, alpha=0.6, lw=0, zorder=2)
        above, below = int((y > YLIM[1]).sum()), int((y < YLIM[0]).sum())
        if above:
            ax.text(i, YLIM[1] - 0.05, f"+{above} above", ha="center", va="top", fontsize=8.5,
                    color=BLUE, fontweight="bold",
                    bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.85))
        if below:
            ax.text(i, YLIM[0] + 0.05, f"+{below} below", ha="center", va="bottom", fontsize=8.5,
                    color=BLUE, fontweight="bold",
                    bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.85))
        rmse = stat(level, est, "rmse")
        ax.text(i, -0.17, f"RMSE {rmse:.2f}", transform=ax.get_xaxis_transform(), ha="center", va="top",
                fontsize=8.5, color=DARK_GOLD if est == "Oracle TMLE" else st["colour"],
                fontweight="bold" if est == "C-TMLE (greedy)" else "normal")
    ax.text(-0.55, TRUE_ATE + 0.06, "true effect = 2", ha="left", va="bottom", fontsize=9,
            color=DARK_GOLD, fontweight="bold")
    ax.set_xticks(range(len(ORDER)), [STYLES[e]["short"] for e in ORDER], fontsize=9.5)
    for tick, est in zip(ax.get_xticklabels(), ORDER):
        tick.set_color(DARK_GOLD if est == "Oracle TMLE" else STYLES[est]["colour"])
    ax.set_xlim(-0.6, len(ORDER) - 0.4)
    ax.set_ylim(*YLIM)
    ax.set_ylabel("Estimated treatment effect")
    # family brackets above the axis
    spans = [("none", 0, 0), ("all", 1, 3), ("ctmle", 4, 5), ("oracle", 6, 6)]
    for fam, a, b in spans:
        label, colour = FAMILY_LABEL[fam]
        ax.plot([a - 0.3, b + 0.3], [1.035, 1.035], color=colour, lw=1.5, transform=ax.get_xaxis_transform(),
                clip_on=False)
        ax.text((a + b) / 2, 1.05, label, ha="center", va="bottom", fontsize=8.5, color=colour,
                transform=ax.get_xaxis_transform())


def strength_headline(level: float) -> str:
    aipw, ctmle = stat(level, "One-step (AIPW)", "rmse"), stat(level, "C-TMLE (greedy)", "rmse")
    if level == 0:
        return "No instruments: every adjusted estimator finds the true effect"
    return (f"Instrument strength {level:.1f}: AIPW's error is {aipw / ctmle:.1f} times C-TMLE's"
            if aipw / ctmle >= 1.15 else
            f"Instrument strength {level:.1f}: weak instruments, and the adjusted estimators still tie")


def strip_figure(level: float, title: str, subtitle: str, dpi: int = 200):
    fig, ax = plt.subplots(figsize=(11, 5.6))
    fig.subplots_adjust(top=0.77, bottom=0.2, left=0.07, right=0.99)
    strip(ax, level)
    frame(fig, title, subtitle)
    return fig


def plot_strong() -> None:
    level = max(LEVELS)
    aipw, ctmle = stat(level, "One-step (AIPW)", "rmse"), stat(level, "C-TMLE (greedy)", "rmse")
    fig = strip_figure(level,
                       f"With strong instruments, AIPW's error is {aipw / ctmle:.1f} times C-TMLE's",
                       f"Estimated effect in each of 100 simulated datasets at instrument strength {level:.0f}. "
                       "Unweighted TMLE is unstable, with some estimates\nfar off the scale; C-TMLE stays "
                       "almost as tight as the oracle without being told which covariates matter.")
    fig.savefig(FIGS / "estimates_strong_instruments.png")
    plt.close(fig)
    print("Saved estimates_strong_instruments.png")


def make_gif() -> None:
    frames = []
    for level in LEVELS:
        fig = strip_figure(level, strength_headline(level),
                           "Estimated effect in each of 100 simulated datasets. Instruments affect only who is "
                           "treated, so adjusting for them adds\nnoise, not accuracy. Instrument strength rises "
                           "from 0 to 2 across the frames.")
        # progress dots for the five strengths, top right
        for k, lv in enumerate(LEVELS):
            fig.text(0.86 + k * 0.028, 1.0, "●", fontsize=13, ha="center", va="bottom",
                     color=GOLD if lv == level else "#D3D2E6")
        fig.text(0.84, 1.004, "instrument strength", fontsize=8.5, color=SUBTLE, ha="right", va="bottom")
        buf = io.BytesIO()
        fig.savefig(buf, format="png", dpi=110)
        plt.close(fig)
        buf.seek(0)
        frames.append(Image.open(buf).convert("RGB"))
    size = frames[0].size
    frames = [f.resize(size) for f in frames]
    frames = [f.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
    durations = [2200] * (len(frames) - 1) + [4500]
    frames[0].save(FIGS / "instrument_sweep.gif", save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, optimize=True)
    print("Saved instrument_sweep.gif")


if __name__ == "__main__":
    plot_by_strength()
    plot_strong()
    make_gif()
