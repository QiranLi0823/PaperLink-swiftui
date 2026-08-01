@title{
  title = "A Novel Trajectory Prediction Framework Based on Transformer"

  @author{
    name = "Author One"
    affiliation = "Tsinghua University, Department of Computer Science"
    email = "author1@tsinghua.edu.cn"
    orcid = "0000-0001-2345-6789"
    note = "equal_contribution"
  }

  @author{
    name = "Author Two"
    affiliation = "Peking University, School of Artificial Intelligence"
    email = "author2@pku.edu.cn"
    orcid = "0000-0002-3456-7890"
    note = "equal_contribution"
  }

  @author{
    name = "Author Three"
    affiliation = "Zhejiang University, College of Computer Science"
    email = "author3@zju.edu.cn"
    corresponding = "true"
  }

  @footnote{
    marker = "†"
    label = "equal_contribution"
    These authors contributed equally to this work.
  }

  @footnote{
    marker = "*"
    label = "corresponding"
    Corresponding author: author3@zju.edu.cn
  }
}

@abstract{
  keywords = ["Trajectory Prediction", "Transformer", "Autonomous Driving", "Deep Learning", "Social Attention"]
Trajectory prediction is a critical component for autonomous driving systems. In this paper, we propose a novel framework that leverages the Transformer architecture for multi-agent trajectory prediction. Our method achieves state-of-the-art performance on the ETH-UCY and nuScenes datasets, demonstrating significant improvements over existing approaches.
}

@section Introduction

Predicting the future trajectories of surrounding agents is crucial for autonomous vehicles @cite{gupta2018social}. Recent advances in deep learning have enabled significant progress in this domain @cite{alahi2016social}. However, existing methods often struggle with complex multi-agent interactions.

As shown in @ref{fig:framework}, our framework consists of three main components: an encoder for historical trajectories, a social attention module for agent interactions, and a decoder for future trajectory prediction.

@figure{
  path = "figures/framework.png"
  caption = "Overview of the proposed trajectory prediction framework. The system takes historical trajectories as input and predicts future positions through social-aware attention mechanisms."
  label = "fig:framework"
}

@section Related Work

@subsection Trajectory Prediction

Traditional trajectory prediction methods rely on hand-crafted features and physics-based models @cite{helbing1995social}. With the advent of deep learning, recurrent neural networks have become the dominant approach @cite{alahi2016social}.

@subsection Transformer in Motion Forecasting

The Transformer architecture @cite{vaswani2017attention} has shown remarkable success in sequence modeling tasks. Recent works have adapted Transformers for trajectory prediction @cite{yuan2021agentformer}.

@section Method

@subsection Problem Formulation

Given the observed trajectory of $N$ agents over $T_{obs}$ timesteps, denoted as $X = \{x_i^t\}_{i=1,t=1}^{N,T_{obs}}$ where $x_i^t \in \mathbb{R}^2$ represents the 2D position of agent $i$ at time $t$, our goal is to predict their future trajectories $Y = \{y_i^t\}_{i=1,t=T_{obs}+1}^{N,T_{obs}+T_{pred}}$.

@equation{
  content = "\hat{Y} = f_{\theta}(X) = \text{Decoder}(\text{SocialAttn}(\text{Encoder}(X)))"
  label = "eq:framework"
}

@subsection Network Architecture

Our encoder processes each agent's historical trajectory independently using a Transformer encoder. The social attention module then models interactions between agents.

@subsection Loss Function

We train our model using a combination of regression loss and a diversity loss to encourage multi-modal predictions:

@equation{
  content = "\mathcal{L} = \mathcal{L}_{reg} + \lambda \mathcal{L}_{div} = \min_k \|\hat{Y}^k - Y\|_2^2 + \lambda \cdot \text{Var}(\{\hat{Y}^k\})"
  label = "eq:loss"
}

@section Experiments

@subsection Datasets

We evaluate our method on two widely-used benchmarks: ETH-UCY @cite{pellegrini2009eth} and nuScenes @cite{caesar2020nuscenes}. The ETH-UCY dataset contains pedestrian trajectories in various scenarios, while nuScenes provides vehicle trajectories in urban environments.

@subsection Evaluation Metrics

We use two standard metrics for evaluation: Average Displacement Error (ADE) and Final Displacement Error (FDE).

@subsection Quantitative Results

@table{
  caption = "Comparison with state-of-the-art methods on ETH-UCY dataset (ADE/FDE in meters)"
  label = "tab:eth_results"
  columns = ["Method", "ETH", "Hotel", "Univ", "Zara1", "Zara2", "Avg"]
  rows = [
    ["Social-GAN", "0.81/1.52", "0.72/1.61", "0.60/1.26", "0.34/0.69", "0.42/0.84", "0.58/1.18"],
    ["Trajectron++", "0.67/1.18", "0.43/0.86", "0.56/1.17", "0.31/0.62", "0.34/0.70", "0.46/0.91"],
    ["AgentFormer", "0.45/0.75", "0.14/0.22", "0.25/0.45", "0.18/0.30", "0.14/0.24", "0.23/0.39"],
    ["Ours", "0.40/0.68", "0.12/0.19", "0.22/0.40", "0.15/0.26", "0.12/0.21", "0.20/0.35"]
  ]
}

As shown in @ref{tab:eth_results}, our method achieves the best performance across all scenarios on the ETH-UCY dataset.

@subsection Ablation Study

We conduct ablation studies to analyze the contribution of each component:

@table{
  caption = "Ablation study on the ETH-UCY dataset"
  label = "tab:ablation"
  columns = ["Configuration", "ADE", "FDE"]
  rows = [
    ["Full model", "0.20", "0.35"],
    ["w/o Social Attention", "0.28", "0.49"],
    ["w/o Diversity Loss", "0.24", "0.42"],
    ["w/o Transformer Encoder", "0.31", "0.55"]
  ]
}

The results in @ref{tab:ablation} demonstrate that each component contributes to the final performance.

@subsection Qualitative Results

@figure{
  path = "figures/qualitative.png"
  caption = "Qualitative comparison of trajectory predictions. Our method (green) produces more accurate predictions compared to baselines (red, blue). Ground truth is shown in black."
  label = "fig:qualitative"
}

@ref{fig:qualitative} shows qualitative comparisons between our method and baseline approaches.

@section Conclusion

We presented a novel Transformer-based framework for multi-agent trajectory prediction. Our method effectively models social interactions through attention mechanisms and achieves state-of-the-art performance on standard benchmarks. Future work will explore incorporating map information and extending to longer prediction horizons.
