// SPDX-License-Identifier: GPL-2.0-only
/*
 * Recovery-only compatibility hooks for the stock fire FocalTech module.
 *
 * OrangeFox does not run the proximity sensor stack. The stock touchscreen
 * module still links against its notifier entry points, even though recovery
 * never uses proximity mode. Keep these hooks deliberately inert so the
 * original touchscreen module can be loaded without starting SCP and the
 * complete sensor stack.
 */

#include <linux/module.h>
#include <linux/notifier.h>

int ps_enable_register_notifier(struct notifier_block *notifier)
{
	(void)notifier;
	return 0;
}
EXPORT_SYMBOL_GPL(ps_enable_register_notifier);

int tpd_notifier_call_chain(unsigned long event, void *data)
{
	(void)event;
	(void)data;
	return 0;
}
EXPORT_SYMBOL_GPL(tpd_notifier_call_chain);

MODULE_DESCRIPTION("Xiaomi fire recovery touchscreen compatibility hooks");
MODULE_LICENSE("GPL");
