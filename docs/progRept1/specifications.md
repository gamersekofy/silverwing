# Math 448 Progress Report 1: Agent Execution Master Plan

### Phase 1: Environment Setup & Data Pipeline (Pre-Tasks)

1. **Load Raw Data:**
* Import `USvideos.csv` (Mitchell Jolly Kaggle dataset, $n \approx 40,949$, $p = 16$) into R or Python.

2. **Implement Baseline Preprocessing & Feature Engineering:**
* **Deduplication:** Deduplicate records by `video_id` or aggregate snapshots to resolve multi-day trending data leakage.
* **Missing/Disabled Data:** Identify and handle `comments_disabled`, `ratings_disabled`, and `video_error_or_removed` records.
* **Log Transformations:** Create transformed log-response variables: $\log(1 + \text{views})$, $\log(1 + \text{likes})$, $\log(1 + \text{comment\_count})$ to fix severe right-skewness.
* **Derived Predictors:** Extract `publish_hour`, `publish_dayofweek`, `title_length` (character count), `title_word_count`, and `tag_count`.

3. **Data Cleaning Summary Metrics:**
* Record exact observation counts before and after each cleaning step (e.g., initial $N$, rows dropped due to missingness/outliers, final $N$) to document in the data prep section.

---

### Phase 2: Exploratory Data Analysis (EDA) & Visualizations

Generate clear, publication-quality plots (saved as images for the main text) and numerical summaries:

1. **Response Distributions:**
* Histograms comparing raw `views` vs. $\log(1 + \text{views})$ to justify log transformation.

2. **Categorical & Metadata Relationships:**
* Boxplots of $\log(\text{views})$ and engagement ratios ($\frac{\text{likes}}{\text{views}}$, $\frac{\text{comments}}{\text{views}}$) grouped by `category_id`.
* Boxplots comparing engagement metrics when `comments_disabled` or `ratings_disabled` are `TRUE` vs `FALSE`.

3. **Temporal & Text Metrics:**
* Bar plots / Line charts showing average engagement across `publish_hour` and `publish_dayofweek`.
* Scatter plots with trendlines: `title_length` vs. $\log(\text{views})$ and `tag_count` vs. $\log(\text{views})$.

4. **Multicollinearity & Correlations:**
* A correlation heatmap or pairs plot matrix across all numerical predictors and response variables to identify feature interactions and potential collinearity.

---

### Phase 3: Core Report Drafting (Main Text)

Draft the written report following the structure modeled in the sample progress reports:

#### Section 1: Introduction & Objective

* Reiterate the problem statement: predicting YouTube video engagement and understanding the effect of upload metadata.
* Clearly define the research questions:
  * *Regression:* Predict continuous metrics ($\log(\text{views})$, engagement ratios).
  * *Classification:* Predict "High Engagement" status (top quartile views/engagement).

#### Section 2: Data Overview & Preprocessing

* **Data Source:** Mitchell Jolly YouTube Trending Dataset (Kaggle).
* **Dataset Characteristics:** Define observation counts, variables, outcomes, and predictors in a clear summary table (variable name, type, description).
* **Cleaning & Preprocessing Steps:** Document the cleaning pipeline step-by-step, detailing raw data state, filtering steps, missing value handling, and log transformations with full mathematical/logical justification.

#### Section 3: Exploratory Data Analysis & Data Issues

* Embed EDA figures into the document alongside narrative descriptions of key findings.
* Explicitly address data issues:
* Heavy right-skewness in view/like counts.
* Potential temporal data leakage from repeated trending snapshot dates.
* Absence of baseline channel-level covariates (e.g., total channel subscriber count).
* Outliers and severe class imbalances in specific categories or binary flags.

#### Section 4: Initial Modeling Plan & Appropriate Methods

* Detail candidate supervised learning approaches and justify why each fits the dataset characteristics:
  * **Regularized Regression (LASSO / Ridge):** Handles collinearity and high-dimensional categorical features (categories/tags).
  * **Tree-Based Ensembles (Random Forest / Gradient Boosting):** Captures complex non-linear interaction effects (e.g., title length impact varying by video category).
  * **Classification Models (Logistic Regression & SVM):** Categorizes binary engagement tiers (Linear vs. RBF kernels).

* Outline the validation framework: 10-fold cross-validation evaluated via RMSE (regression) and ROC-AUC / Error Rate (classification).

---

### **Phase 4: Assembly, Code Appendix & Formatting (Post-Tasks)**

1. **Code Appendix Preparation:**
  * Consolidate all R / Python scripts used for loading, cleaning, calculating summary outputs, and generating graphics.
  * Ensure code is clean, well-commented, and includes output summary tables (e.g., `summary()` statistical tables).

2. **Document Compilation:**
  * Compile the main text write-up along with embedded visualizations and the code appendix into a single, cohesive PDF document.

3. **Quality Check against Rubric Checklist:**

* [ ] Research/prediction question clearly defined.
* [ ] Data source, observations, predictors, and outcome described.
* [ ] Preprocessing and cleaning choices justified.
* [ ] EDA summaries and visualizations included.
* [ ] Data issues (missing data, skewness, leakage, outliers) identified.
* [ ] Initial modeling plan outlined with justification.
* [ ] Code appendix attached as PDF.
