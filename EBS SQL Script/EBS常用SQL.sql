--按客户统计环年销售（含税）和成本
select ra.bill_to_customer_id,
       hp.party_name,
       count(distinct ral.sales_order),
       sum(ral.extended_amount),,
       sum(cux_fin_pub.get_trx_line_cost(ral.customer_trx_line_id) *
           ral.quantity_invoiced)
/*rbs.name, ra.trx_number, ra.trx_date, ra.bill_to_customer_id, hp.party_name, ral.sales_order,
ral.interface_line_attribute6,  ral.extended_amount,
cux_fin_pub.get_trx_line_cost(ral.customer_trx_line_id)*ral.quantity_invoiced line_cost*/
  from ra_customer_trx_all ra
  join ra_customer_trx_lines_all ral
    on ra.customer_trx_id = ral.customer_trx_id
  join hz_cust_accounts hca
    on ra.bill_to_customer_id = hca.cust_account_id
  join hz_parties hp
    on hca.party_id = hp.party_id
  join ra_batch_sources_all rbs
    on rbs.batch_source_id = ra.batch_source_id
   and rbs.org_id = ra.org_id
   and rbs.name = 'OM 导入'
 where ra.org_id = '95' --北京组织
   and to_char(ra.trx_date, 'yyyy-mm') >= '2015-11' -- 环年
   and to_char(ra.trx_date, 'yyyy-mm') < '2016-11' -- 2015-11 到 2016-10
 group by ra.bill_to_customer_id, hp.party_name

-- 电商PO和SO关联对应关系：
 SELECT CPL.PO_ORDER_NUMBER, --电商平台采购订单编号
       POH.SEGMENT1,--采购订单编号
       OOH.ORDER_NUMBER,--ISO订单编号
       --OOH2.ORDER_NUMBER,--SO编号
       CPL.ITEM_NUMBER,--商品编号
       MSIT.DESCRIPTION,--商品名称
       --CPL.RECEIVE_OE_LINE_ID,--ISO行ID
       --CPL.OE_LINE_ID,--SO行ID
       --CPL.EBS_PO_LINE_ID,--PO行ID
       CPL.ORDER_QUANTITY,--数量
       CPL.UNIT_PRICE --含税单价
  FROM cux_ec_po_line_intf CPL,
       MTL_SYSTEM_ITEMS_B MSIT,
       PO_LINES_ALL POL,
       PO_HEADERS_ALL POH,
       OE_ORDER_LINES_ALL OOL,
       OE_ORDER_HEADERS_ALL OOH,
       OE_ORDER_LINES_ALL OOL2,
       OE_ORDER_HEADERS_ALL OOH2
 WHERE NVL(CPL.OE_LINE_ID, 0) <> 0
   AND NVL(CPL.RECEIVE_OE_LINE_ID, 0) <> 0
   AND CPL.EXECUTE_STAUTS='S'
   AND CPL.RECEIVE_ORG_ID=MSIT.ORGANIZATION_ID
   AND CPL.ITEM_NUMBER=MSIT.SEGMENT1
   AND CPL.EBS_PO_LINE_ID=POL.PO_LINE_ID
   AND POL.PO_HEADER_ID=POH.PO_HEADER_ID
   AND CPL.RECEIVE_OE_LINE_ID=OOL.LINE_ID
   AND OOL.HEADER_ID=OOH.HEADER_ID
   AND CPL.OE_LINE_ID=OOL2.LINE_ID
   AND OOL2.HEADER_ID=OOH2.HEADER_ID
