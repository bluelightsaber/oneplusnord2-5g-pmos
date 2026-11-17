#!/usr/bin/env python3
"""Add a FIFO-only (no APDMA) mode to drivers/i2c/busses/i2c-mt65xx.c for MT6893 i2c10..i2c13.

Those controllers (11017000, 1101a000, 1101b000, 11007000) have no AP-DMA channel: the vendor tree marks them
"mediatek,fifo_only" with a single reg entry, and the mainline driver (DMA only) fails with -EINVAL. denniz needs
i2c11 for its MP2650 charger (0x5c). FIFO mode moves at most 8 bytes per message through OFFSET_DATA_PORT, which
is plenty for register access. Usage: patch-i2c-fifo.py KERNEL_TREE
"""
import sys
p = sys.argv[1] + '/drivers/i2c/busses/i2c-mt65xx.c'
s = open(p).read()

def sub(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:60], s.count(old))
    s = s.replace(old, new)

sub('\tvoid __iomem *pdmabase;\t\t/* dma base address*/\n',
    '\tvoid __iomem *pdmabase;\t\t/* dma base address*/\n'
    '\tbool fifo_only;\t\t\t/* denniz: no APDMA channel (i2c10..13) */\n')

# init_hw: no DMA resets, no DMA enable bits
sub('\tif (i2c->dev_comp->apdma_sync) {\n\t\twritel(I2C_DMA_WARM_RST, i2c->pdmabase + OFFSET_RST);',
    '\tif (i2c->fifo_only) {\n\t\tmtk_i2c_writew(i2c, I2C_SOFT_RST, OFFSET_SOFTRESET);\n'
    '\t} else if (i2c->dev_comp->apdma_sync) {\n\t\twritel(I2C_DMA_WARM_RST, i2c->pdmabase + OFFSET_RST);')
sub('\tif (i2c->dev_comp->dma_sync)\n\t\tcontrol_reg |= I2C_CONTROL_DMAACK_EN | I2C_CONTROL_ASYNC_MODE;\n',
    '\tif (i2c->fifo_only)\n\t\tcontrol_reg &= ~I2C_CONTROL_DMA_EN;\n'
    '\telse if (i2c->dev_comp->dma_sync)\n\t\tcontrol_reg |= I2C_CONTROL_DMAACK_EN | I2C_CONTROL_ASYNC_MODE;\n')

fifo_fn = r'''
#define MTK_I2C_FIFO_DEPTH 8

/* denniz: PIO transfer through the 8-byte FIFO, for controllers without an APDMA channel. One message (or one
 * write-then-read pair) per call, no auto restart. */
static int mtk_i2c_do_transfer_fifo(struct mtk_i2c *i2c, struct i2c_msg *msgs, int left_num)
{
	struct i2c_msg *wr = NULL, *rd = NULL;
	u16 control_reg, irqs = I2C_HS_NACKERR | I2C_ACKERR | I2C_ARB_LOST | I2C_TRANSAC_COMP;
	int i, ret;

	if (i2c->op == I2C_MASTER_WRRD) {
		wr = msgs;
		rd = msgs + 1;
	} else if (i2c->op == I2C_MASTER_RD) {
		rd = msgs;
	} else {
		wr = msgs;
	}
	if ((wr && wr->len > MTK_I2C_FIFO_DEPTH) || (rd && rd->len > MTK_I2C_FIFO_DEPTH) ||
	    (wr && !wr->len) || (rd && !rd->len))
		return -EOPNOTSUPP;

	i2c->irq_stat = 0;
	reinit_completion(&i2c->msg_complete);

	control_reg = mtk_i2c_readw(i2c, OFFSET_CONTROL) &
		~(I2C_CONTROL_DIR_CHANGE | I2C_CONTROL_RS | I2C_CONTROL_DMA_EN);
	if (left_num >= 1)
		control_reg |= I2C_CONTROL_RS;
	if (i2c->op == I2C_MASTER_WRRD)
		control_reg |= I2C_CONTROL_DIR_CHANGE | I2C_CONTROL_RS;
	mtk_i2c_writew(i2c, control_reg, OFFSET_CONTROL);

	mtk_i2c_writew(i2c, i2c_8bit_addr_from_msg(msgs), OFFSET_SLAVE_ADDR);
	mtk_i2c_writew(i2c, irqs, OFFSET_INTR_STAT);
	mtk_i2c_writew(i2c, I2C_FIFO_ADDR_CLR, OFFSET_FIFO_ADDR_CLR);
	mtk_i2c_writew(i2c, irqs, OFFSET_INTR_MASK);

	if (i2c->op == I2C_MASTER_WRRD) {
		if (i2c->dev_comp->aux_len_reg) {
			mtk_i2c_writew(i2c, wr->len, OFFSET_TRANSFER_LEN);
			mtk_i2c_writew(i2c, rd->len, OFFSET_TRANSFER_LEN_AUX);
		} else {
			mtk_i2c_writew(i2c, wr->len | (rd->len << 8), OFFSET_TRANSFER_LEN);
		}
		mtk_i2c_writew(i2c, I2C_WRRD_TRANAC_VALUE, OFFSET_TRANSAC_LEN);
	} else {
		mtk_i2c_writew(i2c, msgs->len, OFFSET_TRANSFER_LEN);
		mtk_i2c_writew(i2c, 1, OFFSET_TRANSAC_LEN);
	}

	if (wr)
		for (i = 0; i < wr->len; i++)
			mtk_i2c_writew(i2c, wr->buf[i], OFFSET_DATA_PORT);

	mtk_i2c_writew(i2c, I2C_TRANSAC_START, OFFSET_START);
	ret = wait_for_completion_timeout(&i2c->msg_complete, i2c->adap.timeout);
	mtk_i2c_writew(i2c, ~irqs, OFFSET_INTR_MASK);

	if (ret == 0) {
		dev_dbg(i2c->dev, "addr: %x, fifo transfer timeout\n", msgs->addr);
		mtk_i2c_init_hw(i2c);
		return -ETIMEDOUT;
	}
	if (i2c->irq_stat & (I2C_HS_NACKERR | I2C_ACKERR)) {
		dev_dbg(i2c->dev, "addr: %x, fifo transfer ACK error\n", msgs->addr);
		mtk_i2c_init_hw(i2c);
		return -ENXIO;
	}
	if (rd)
		for (i = 0; i < rd->len; i++)
			rd->buf[i] = mtk_i2c_readw(i2c, OFFSET_DATA_PORT) & 0xff;
	return 0;
}
'''
sub('\nstatic int mtk_i2c_do_transfer(struct mtk_i2c *i2c, struct i2c_msg *msgs,\n',
    fifo_fn + '\nstatic int mtk_i2c_do_transfer(struct mtk_i2c *i2c, struct i2c_msg *msgs,\n')

sub('\tint ret;\n\n\ti2c->irq_stat = 0;\n\n\tif (i2c->auto_restart)\n\t\trestart_flag = I2C_RS_TRANSFER;\n',
    '\tint ret;\n\n\tif (i2c->fifo_only)\n\t\treturn mtk_i2c_do_transfer_fifo(i2c, msgs, left_num);\n\n'
    '\ti2c->irq_stat = 0;\n\n\tif (i2c->auto_restart)\n\t\trestart_flag = I2C_RS_TRANSFER;\n')

sub('\ti2c->auto_restart = i2c->dev_comp->auto_restart;\n',
    '\ti2c->auto_restart = i2c->fifo_only ? 0 : i2c->dev_comp->auto_restart;\n')

sub('\ti2c->pdmabase = devm_platform_get_and_ioremap_resource(pdev, 1, NULL);\n'
    '\tif (IS_ERR(i2c->pdmabase))\n\t\treturn PTR_ERR(i2c->pdmabase);\n',
    '\ti2c->fifo_only = of_property_read_bool(pdev->dev.of_node, "mediatek,fifo_only");\n'
    '\tif (!i2c->fifo_only) {\n'
    '\t\ti2c->pdmabase = devm_platform_get_and_ioremap_resource(pdev, 1, NULL);\n'
    '\t\tif (IS_ERR(i2c->pdmabase))\n\t\t\treturn PTR_ERR(i2c->pdmabase);\n\t}\n')

sub('\ti2c->clocks[I2C_MT65XX_CLK_DMA].clk = devm_clk_get(&pdev->dev, "dma");\n',
    '\ti2c->clocks[I2C_MT65XX_CLK_DMA].clk = i2c->fifo_only ?\n'
    '\t\tdevm_clk_get_optional(&pdev->dev, "dma") : devm_clk_get(&pdev->dev, "dma");\n')
open(p, 'w').write(s)
print('patched', p)
