# 通用 Web3 詞彙字典

給 `--initial-prompt` 用的通用 Web3/加密貨幣領域專有名詞，只收公開、通用的
產業詞彙（知名交易所、公鏈、協議、公開人物、行業術語）——**不收任何特定公司
內部的人名/產品名**，那些屬於使用者自己的私有資料，應該另外存在私有的地方。

## 公鏈 / L1 / L2

- Ethereum、Solana、Bitcoin、BNB Chain、Base、Arbitrum、Optimism、Polygon、Sui
- Avalanche、Cronos、Fantom

## 開發公司 / 基金會

- Mysten Labs

## 交易所

- Binance、OKX、Coinbase、Bybit、KuCoin

## DeFi / 永續合約 / 預測市場

- Aave、Hyperliquid、GMX、dYdX、Jupiter
- Polymarket、Kalshi、PredictFun

## 其他常見協議 / 產品

- Aster、River、Euphoria、icbox.io

## 術語

- DeFi、TGE
- LRT、restaking、staking、bridge
- perp
- tokenized stock
- signless trading
- Solidity

## 電競

- CS2、英雄聯盟、瓦羅蘭

## 公開人物

- Sam Altman、Mark Zuckerberg、Justin Sun、Arthur Hayes
- Satoshi Nakamoto、Vitalik Buterin
- Anatoly Yakovenko、Raj Gokal

---

## 使用方式

跟 `--initial-prompt` 搭配用，把想要的類別轉成一段自然語句餵給模型，例如：

```bash
mlx_whisper meeting.wav \
  --model mlx-community/whisper-large-v3-turbo \
  --initial-prompt "這場會議討論到 Aave、Hyperliquid、GMX、Polymarket、PredictFun、Binance、OKX、DeFi、TGE、LRT、restaking、CS2、英雄聯盟、瓦羅蘭。" \
  -f json -o .
```

如果你有自己的私有詞彙（公司內部人名/產品名），把私有字典的內容附加在後面
一起組成 prompt 即可，不需要放進這份公開檔案。
