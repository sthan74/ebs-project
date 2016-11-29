-- MOAC权限控制
begin
  mo_global.init('CUX');
end;

--查找销售人员
select * from jtf_rs_defresources_srp_v v
where v.name like '刘玉明%'

-- 按销售人员统计环年收入和成本匹配
select ctl.extended_amount,
       ooha.order_number,
       ctl.sales_order,
       hp.party_name,
       ct.trx_number,
       ct.trx_date,
       --ctl.interface_line_attribute6,
       --  oola.line_type_id,
       ottl.name,
       --  ooha.order_type_id,
       otth.name,
       oola.ordered_item,
       msib.description,
       oola.ordered_quantity,
       decode(ctl.quantity_invoiced,
              NULL,
              ctl.quantity_credited,
              ctl.quantity_invoiced) as invoiced_quantity,
       cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) as unit_cost,
       nvl(cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) *
           decode(ctl.quantity_invoiced,
                  NULL,
                  ctl.quantity_credited,
                  ctl.quantity_invoiced),
           0) as total_cost,
       ctl.extended_amount - nvl(cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) *
                                 decode(ctl.quantity_invoiced,
                                        NULL,
                                        ctl.quantity_credited,
                                        ctl.quantity_invoiced),
                                 0) as margin
  from ra_customer_trx_lines_all ctl
  join ra_customer_trx_all ct
    on ct.customer_trx_id = ctl.customer_trx_id
   and ct.primary_salesrep_id = '100005253' -- and ct.trx_number = '10000005011'
   and ct.trx_date between to_date('2016-01-01', 'yyyy-mm-dd') and
       to_date('2016-12-31', 'yyyy-mm-dd')
  join(oe_order_lines_all oola
  join oe_order_headers ooha
    on ooha.header_id = oola.header_id
  join oe_transaction_types otth
    on ooha.order_type_id = otth.transaction_type_id
  join oe_transaction_types ottl
    on oola.line_type_id = ottl.transaction_type_id --and ottl.transaction_type_id = 1254
 ) on oola.line_id = ctl.interface_line_attribute6
  join mtl_system_items_b msib
    on oola.ship_from_org_id = msib.organization_id
   and oola.inventory_item_id = msib.inventory_item_id
  join hz_cust_accounts hca
    on ct.bill_to_customer_id = hca.cust_account_id
  join hz_parties hp
    on hca.party_id = hp.party_id

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

-- 查询出库、PO保留、PO生成等有问题的电商调拨单
-- cux_hst_ec_po_oe_status_view 视图
create or replace view cux_hst_ec_po_oe_status_view as
select haou.name as buyer_org,
       pli.item_number,
       msib.description as item_desc,
       pha.segment1 as po_num,
       plla.quantity_received as po_rev_qty,
       oolaout.ordered_quantity as po_qty,
       pli.reservate_flag as po_rev_flag,
       oohaout.order_number as cust_ordnum,
       oolaout.attribute17 as ec_cust_num,
       oolaout.flow_status_code as cust_line_status,
       haou1.name as seller_org,
       oohain.order_number as seller_so,
       oolain.attribute17 as ec_seller_so,
       oolain.ordered_quantity as seller_ord_qty,
       oolain.shipped_quantity as seller_shp_qty,
       oolain.flow_status_code as seller_line_status,
       oohi.sheet_type as seller_so_type,
       pli.execute_stauts as po_itf_status,
       pli.execute_message as po_itf_message
  from cux_ec_po_line_intf pli
  join oe_order_lines_all oolaout
    on oolaout.line_id = pli.oe_line_id
   and oolaout.flow_status_code = 'AWAITING_SHIPPING'
  join oe_order_headers_all oohaout
    on oohaout.header_id = oolaout.header_id
  left join po_line_locations_all plla
    on pli.ebs_po_line_id = plla.po_line_id
  left join po_headers_all pha on pha.po_header_id = plla.po_header_id
  join mtl_system_items_b msib
    on msib.inventory_item_id = oolaout.inventory_item_id
   and msib.organization_id = oolaout.ship_from_org_id
  join oe_order_lines_all oolain
    on oolain.line_id = pli.receive_oe_line_id
  join oe_order_headers_all oohain
    on oolain.header_id = oohain.header_id
  join hr_all_organization_units haou
    on haou.organization_id = oolaout.ship_from_org_id
  join hr_all_organization_units haou1
    on haou1.organization_id = oolain.ship_from_org_id
  join cux_ec_oe_order_line_intf ooli
    on pli.receive_oe_line_id = ooli.ebs_order_line_id
  join cux_ec_oe_order_header_intf oohi
    on oohi.online_order_number = ooli.online_order_number

-- 按部门查询费用－－YUM 2016年统计
select gcc.segment3,
     --  gjl.period_name,
       sum(gjl.accounted_dr),
       sum(gjl.accounted_cr)
  from gl_je_lines gjl
  join gl_code_combinations gcc
    on gjl.code_combination_id = gcc.code_combination_id
   and gcc.segment2 = '1030201'
   and gcc.segment3 not like '2221%'
 where gjl.ledger_id = 2021
   and gjl.period_name like '16%'
 group by gcc.segment3--, gjl.period_name
 order by gjl.period_name
