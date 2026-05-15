CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.generate_cfg_data
(
    id                            string,
    securityId                    string,
    securityExchange              string,
    businessType                  string,
    securityPosition              float64,
    minSpread                     float64,
    minReportBalance              float64,
    avgSingleReportBalance        float64,
    callAuctionRatio              float64,
    continousAuctionRatio         float64,
    execBalanceRequire            float64,
    execBalanceRatio              float64,
    timeWeightReportPriceDiff     float64,
    continousAuctionEffectRatio   float64,
    lastNoReportPriceTime         string,
    canceledReportRatio           float64,
    canceledNum                   float64,
    singleExecRatio               float64,
    execAmountExceedHistoryAvgRatio float64,
    DeviationQuotationRatio       float64,
    FutureSpotExposure            string,
    MarketMaker                   string
)
AS $$
import random

def generate_records():
    template = [
        '1', '', '1', '4', 100.0,
        0.08, 1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, '0',
        0.0, 0.0, 0.0, 0.0, 0.0,
        '0', 'D890088888'
    ]
    for i in range(100000, 100200):
        row = template.copy()
        row[0] = str(i - 99999)
        row[1] = str(i)
        row[5] = random.uniform(0.1, 0.9)
        row[6] = random.uniform(100, 10000)
        yield tuple(row)
$$
SETTINGS type = 'python', read_function_name = 'generate_records';
